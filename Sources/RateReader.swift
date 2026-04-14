import Foundation

/// Server-provided rate limit data
struct RateLimit: Equatable {
    let fiveHourPct: Double
    let sevenDayPct: Double?
    let fiveHourResetsAt: Date?
    let updatedAt: Date  // file modification time
}

enum ClaudeRateStatus: Equatable {
    case available
    case waitingForSessionData
    case rateLimitsUnavailable
}

/// Shared: normalizes Unix timestamps that may be seconds or milliseconds.
func normalizeTimestamp(_ value: Double) -> Date {
    value > 1_000_000_000_000
        ? Date(timeIntervalSince1970: value / 1000)
        : Date(timeIntervalSince1970: value)
}

// MARK: - Claude Code rate limits (from statusline JSON)

enum ClaudeRateReader {
    private static let defaultFilePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/usage-rate.json")
    private static let defaultCachePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/com.aimeter.app/claude-rate-v1.json")

    static func read() -> RateLimit? {
        inspect().rate
    }

    static func status() -> ClaudeRateStatus {
        inspect().status
    }

    static func inspect(
        filePath: URL = defaultFilePath,
        cachePath: URL = defaultCachePath,
        now: Date = Date()
    ) -> (rate: RateLimit?, status: ClaudeRateStatus) {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return cachedResult(cachePath: cachePath, now: now) ?? (nil, .waitingForSessionData)
        }

        // Check freshness — ignore data older than 6 hours
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath.path),
              let modDate = attrs[.modificationDate] as? Date,
              now.timeIntervalSince(modDate) < 6 * 3600
        else {
            return cachedResult(cachePath: cachePath, now: now) ?? (nil, .waitingForSessionData)
        }

        guard let data = try? Data(contentsOf: filePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return cachedResult(cachePath: cachePath, now: now) ?? (nil, .waitingForSessionData)
        }

        guard let rl = json["rate_limits"] as? [String: Any],
              let fiveHour = rl["five_hour"] as? [String: Any],
              let pct = fiveHour["used_percentage"] as? Double
        else {
            if let cached = cachedResult(cachePath: cachePath, now: now) {
                return cached
            }
            return (nil, .rateLimitsUnavailable)
        }

        let sevenDay = (rl["seven_day"] as? [String: Any])?["used_percentage"] as? Double
        var resetsAt: Date? = nil
        if let ts = fiveHour["resets_at"] as? Double {
            resetsAt = normalizeTimestamp(ts)
        }

        let rate = RateLimit(
            fiveHourPct: pct,
            sevenDayPct: sevenDay,
            fiveHourResetsAt: resetsAt,
            updatedAt: modDate
        )
        writeCache(rate, to: cachePath)
        return (
            rate,
            .available
        )
    }

    private static func cachedResult(cachePath: URL, now: Date) -> (rate: RateLimit, status: ClaudeRateStatus)? {
        guard let cached = readCache(from: cachePath), now.timeIntervalSince(cached.updatedAt) < 6 * 3600 else {
            return nil
        }
        return (cached, .available)
    }

    private static func readCache(from path: URL) -> RateLimit? {
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fiveHourPct = json["fiveHourPct"] as? Double,
              let updatedAtRaw = json["updatedAt"] as? Double
        else { return nil }

        let sevenDayPct = json["sevenDayPct"] as? Double
        let resetsAtRaw = json["fiveHourResetsAt"] as? Double

        return RateLimit(
            fiveHourPct: fiveHourPct,
            sevenDayPct: sevenDayPct,
            fiveHourResetsAt: resetsAtRaw.map(normalizeTimestamp),
            updatedAt: normalizeTimestamp(updatedAtRaw)
        )
    }

    private static func writeCache(_ rate: RateLimit, to path: URL) {
        var json: [String: Any] = [
            "fiveHourPct": rate.fiveHourPct,
            "updatedAt": rate.updatedAt.timeIntervalSince1970,
        ]
        if let sevenDayPct = rate.sevenDayPct {
            json["sevenDayPct"] = sevenDayPct
        }
        if let resetsAt = rate.fiveHourResetsAt?.timeIntervalSince1970 {
            json["fiveHourResetsAt"] = resetsAt
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? data.write(to: path)
    }
}

// MARK: - Codex rate limits (from session JSONL)

enum CodexRateReader {
    static func read() -> RateLimit? {
        let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else { return nil }

        guard let latest = findLatestRollout(in: sessionsDir) else { return nil }

        // Read tail of file (last 100KB) for efficiency
        guard let handle = try? FileHandle(forReadingFrom: latest) else { return nil }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readSize = min(fileSize, 100_000)
        handle.seek(toFileOffset: fileSize - readSize)
        let rawData = handle.readData(ofLength: Int(readSize))
        // Reading from mid-file may split a multi-byte UTF-8 char; use lossy decoding
        let text = String(decoding: rawData, as: UTF8.self)

        // Find last rate_limits event for the main "codex" family.
        // Session JSONL interleaves multiple limit families (codex, codex_bengalfox, etc.);
        // the subscription's primary limit is the one with limit_id == "codex".
        var lastRL: [String: Any]? = nil
        for line in text.split(separator: "\n").reversed() {
            let s = String(line)
            guard s.contains("rate_limits"), s.contains("used_percent") else { continue }
            guard let lineData = s.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  let rl = payload["rate_limits"] as? [String: Any]
            else { continue }
            // Skip auxiliary limit families (e.g. codex_bengalfox); only accept main "codex"
            let limitId = rl["limit_id"] as? String ?? "codex"
            guard limitId == "codex" else { continue }
            lastRL = rl
            break
        }

        guard let rl = lastRL,
              let primary = rl["primary"] as? [String: Any],
              let pct = primary["used_percent"] as? Double
        else { return nil }

        let secondary = (rl["secondary"] as? [String: Any])?["used_percent"] as? Double
        var resetsAt: Date? = nil
        if let ts = primary["resets_at"] as? Double {
            resetsAt = normalizeTimestamp(ts)
        }

        let modDate = (try? FileManager.default.attributesOfItem(atPath: latest.path))?[.modificationDate] as? Date ?? Date()

        return RateLimit(fiveHourPct: pct, sevenDayPct: secondary,
                         fiveHourResetsAt: resetsAt, updatedAt: modDate)
    }

    private static func findLatestRollout(in dir: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var latest: (url: URL, date: Date)? = nil
        while let url = enumerator.nextObject() as? URL {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl" else { continue }
            if let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let mod = vals.contentModificationDate {
                if latest == nil || mod > latest!.date {
                    latest = (url, mod)
                }
            }
        }
        return latest?.url
    }
}

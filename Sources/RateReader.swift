import Foundation

/// Server-provided rate limit data
struct RateLimit: Equatable {
    let fiveHourPct: Double?
    let sevenDayPct: Double?
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
    let updatedAt: Date  // file modification time

    /// The short window normally leads. When the provider temporarily omits
    /// it, the weekly window becomes the only meaningful headline value.
    var headlinePct: Double? { fiveHourPct ?? sevenDayPct }
    var isWeeklyOnly: Bool { fiveHourPct == nil && sevenDayPct != nil }
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
    private static var defaultFilePath: URL { AppPaths.claudeRateFile }
    private static var defaultCachePath: URL { AppPaths.claudeRateCacheFile() }

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

        let sevenDayInfo = rl["seven_day"] as? [String: Any]
        let sevenDay = sevenDayInfo?["used_percentage"] as? Double
        var fiveHourResetsAt: Date? = nil
        if let ts = fiveHour["resets_at"] as? Double {
            fiveHourResetsAt = normalizeTimestamp(ts)
        }
        var sevenDayResetsAt: Date? = nil
        if let ts = sevenDayInfo?["resets_at"] as? Double {
            sevenDayResetsAt = normalizeTimestamp(ts)
        }

        let rate = RateLimit(
            fiveHourPct: pct,
            sevenDayPct: sevenDay,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayResetsAt: sevenDayResetsAt,
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
              let updatedAtRaw = json["updatedAt"] as? Double
        else { return nil }

        let fiveHourPct = json["fiveHourPct"] as? Double
        let sevenDayPct = json["sevenDayPct"] as? Double
        guard fiveHourPct != nil || sevenDayPct != nil else { return nil }
        let fiveHourResetsAtRaw = json["fiveHourResetsAt"] as? Double
        let sevenDayResetsAtRaw = json["sevenDayResetsAt"] as? Double

        return RateLimit(
            fiveHourPct: fiveHourPct,
            sevenDayPct: sevenDayPct,
            fiveHourResetsAt: fiveHourResetsAtRaw.map(normalizeTimestamp),
            sevenDayResetsAt: sevenDayResetsAtRaw.map(normalizeTimestamp),
            updatedAt: normalizeTimestamp(updatedAtRaw)
        )
    }

    private static func writeCache(_ rate: RateLimit, to path: URL) {
        var json: [String: Any] = ["updatedAt": rate.updatedAt.timeIntervalSince1970]
        if let fiveHourPct = rate.fiveHourPct {
            json["fiveHourPct"] = fiveHourPct
        }
        if let sevenDayPct = rate.sevenDayPct {
            json["sevenDayPct"] = sevenDayPct
        }
        if let resetsAt = rate.fiveHourResetsAt?.timeIntervalSince1970 {
            json["fiveHourResetsAt"] = resetsAt
        }
        if let resetsAt = rate.sevenDayResetsAt?.timeIntervalSince1970 {
            json["sevenDayResetsAt"] = resetsAt
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
    /// Cache the "latest rollout" path so we stop stat-ing every file in
    /// ~/.codex/sessions on each poll. The active session keeps the same URL
    /// for its whole lifetime; a full rescan every `fullScanInterval` catches
    /// the case where the user starts a brand-new session.
    private static let cacheLock = NSLock()
    private static var cachedLatestSessionsDir: String?
    private static var cachedLatestURL: URL?
    private static var lastFullScanAt: Date?
    private static let fullScanInterval: TimeInterval = 60

    static func read() -> RateLimit? {
        let sessionsDir = AppPaths.codexSessionsDir
        return read(sessionsDir: sessionsDir)
    }

    static func read(sessionsDir: URL, now: Date = Date()) -> RateLimit? {
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else { return nil }

        guard let latest = latestRollout(in: sessionsDir, now: now) else { return nil }

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
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            let payload = json["payload"] as? [String: Any]
            let topLevelRateLimits = json["rate_limits"] as? [String: Any]
            let payloadRateLimits = payload?["rate_limits"] as? [String: Any]
            let rl = topLevelRateLimits ?? payloadRateLimits
            guard let rl else { continue }
            // Skip auxiliary limit families (e.g. codex_bengalfox); only accept main "codex"
            let limitId = rl["limit_id"] as? String ?? "codex"
            guard limitId == "codex" else { continue }
            lastRL = rl
            break
        }

        guard let rl = lastRL,
              let primary = rl["primary"] as? [String: Any]
        else { return nil }

        struct Window {
            let pct: Double
            let minutes: Int?
            let resetsAt: Date?
        }
        func parseWindow(_ raw: [String: Any]?) -> Window? {
            guard let raw, let pct = raw["used_percent"] as? Double else { return nil }
            let minutes = (raw["window_minutes"] as? NSNumber)?.intValue
            let resetsAt = (raw["resets_at"] as? Double).map(normalizeTimestamp)
            return Window(pct: pct, minutes: minutes, resetsAt: resetsAt)
        }

        let primaryWindow = parseWindow(primary)
        let secondaryWindow = parseWindow(rl["secondary"] as? [String: Any])
        var fiveHour: Window?
        var sevenDay: Window?

        for (window, isPrimary) in [(primaryWindow, true), (secondaryWindow, false)] {
            guard let window else { continue }
            switch window.minutes {
            case 300:
                fiveHour = window
            case 10_080:
                sevenDay = window
            case nil:
                // Backward compatibility for older rollouts that omitted the
                // explicit window length but used primary=5H, secondary=7D.
                if isPrimary { fiveHour = window } else { sevenDay = window }
            default:
                continue
            }
        }
        guard fiveHour != nil || sevenDay != nil else { return nil }

        let modDate = (try? FileManager.default.attributesOfItem(atPath: latest.path))?[.modificationDate] as? Date ?? Date()

        return RateLimit(fiveHourPct: fiveHour?.pct, sevenDayPct: sevenDay?.pct,
                         fiveHourResetsAt: fiveHour?.resetsAt,
                         sevenDayResetsAt: sevenDay?.resetsAt,
                         updatedAt: modDate)
    }

    private static func latestRollout(in dir: URL, now: Date) -> URL? {
        let dirKey = dir.standardizedFileURL.path
        cacheLock.lock()
        let cachedDir = cachedLatestSessionsDir
        let cached = cachedLatestURL
        let lastScan = lastFullScanAt
        cacheLock.unlock()

        let cacheFresh = lastScan.map { now.timeIntervalSince($0) < fullScanInterval } ?? false
        if cacheFresh, cachedDir == dirKey, let cached, FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let found = findLatestRollout(in: dir)
        cacheLock.lock()
        cachedLatestSessionsDir = dirKey
        cachedLatestURL = found
        lastFullScanAt = now
        cacheLock.unlock()
        return found
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

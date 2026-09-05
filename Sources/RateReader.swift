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

        let rl = json["rate_limits"] as? [String: Any]
        let fiveHour = rl?["five_hour"] as? [String: Any]
        let sevenDayInfo = rl?["seven_day"] as? [String: Any]
        let pct = validPercentage(fiveHour?["used_percentage"])
        let sevenDay = validPercentage(sevenDayInfo?["used_percentage"])
        guard pct != nil || sevenDay != nil else {
            if let cached = cachedResult(cachePath: cachePath, now: now) {
                return cached
            }
            return (nil, .rateLimitsUnavailable)
        }

        var fiveHourResetsAt: Date? = nil
        if let ts = fiveHour?["resets_at"] as? Double, ts.isFinite {
            fiveHourResetsAt = normalizeTimestamp(ts)
        }
        var sevenDayResetsAt: Date? = nil
        if let ts = sevenDayInfo?["resets_at"] as? Double, ts.isFinite {
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

    private static func validPercentage(_ raw: Any?) -> Double? {
        guard let pct = raw as? Double, pct.isFinite, (0...100).contains(pct) else { return nil }
        return pct
    }

    private static func readCache(from path: URL) -> RateLimit? {
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updatedAtRaw = json["updatedAt"] as? Double
        else { return nil }

        let fiveHourPct = validPercentage(json["fiveHourPct"])
        let sevenDayPct = validPercentage(json["sevenDayPct"])
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
        try? data.write(to: path, options: .atomic)
    }
}

// MARK: - Codex rate limits (from session JSONL)

enum CodexRateReader {
    private struct CachedFile {
        let mod: Date
        let size: UInt64
        let fileID: UInt64?
        let rate: RateLimit?
    }

    private static let cacheLock = NSLock()
    private static var cachedSessionsDir: String?
    private static var candidates: [URL] = []
    private static var fileCache: [String: CachedFile] = [:]
    private static var lastFullScanAt: Date?
    private static let fullScanInterval: TimeInterval = 60
    private static let maxCandidates = 16
    private static let maxScanBytes: UInt64 = 64 * 1024 * 1024
    private static let maxAge: TimeInterval = 6 * 3600
    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoBasic = ISO8601DateFormatter()

    static func read() -> RateLimit? {
        read(sessionsDir: AppPaths.codexSessionsDir)
    }

    static func read(sessionsDir: URL, now: Date = Date()) -> RateLimit? {
        // Rate polling runs on a background queue; serialize the small cache so
        // changing roots cannot mix snapshots from different installations.
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let key = sessionsDir.standardizedFileURL.path
        if key != cachedSessionsDir {
            cachedSessionsDir = key
            candidates = []
            fileCache = [:]
            lastFullScanAt = nil
        }
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else {
            candidates = []
            fileCache = [:]
            lastFullScanAt = nil
            return nil
        }
        if lastFullScanAt.map({ now.timeIntervalSince($0) >= fullScanInterval || now < $0 }) ?? true {
            candidates = recentRollouts(in: sessionsDir)
            let paths = Set(candidates.map(\.path))
            fileCache = fileCache.filter { paths.contains($0.key) }
            lastFullScanAt = now
        }

        var best: RateLimit?
        for url in candidates {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let mod = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? NSNumber else { continue }
            let fileID = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
            let cached = fileCache[url.path]
            let rate: RateLimit?
            if let cached, cached.mod == mod, cached.size == size.uint64Value, cached.fileID == fileID {
                rate = cached.rate
            } else {
                rate = readLatestRate(from: url, size: size.uint64Value, fallbackDate: mod)
                fileCache[url.path] = CachedFile(mod: mod, size: size.uint64Value, fileID: fileID, rate: rate)
            }
            guard let rate, now.timeIntervalSince(rate.updatedAt) >= 0,
                  now.timeIntervalSince(rate.updatedAt) < maxAge else { continue }
            if best == nil || rate.updatedAt > best!.updatedAt { best = rate }
        }
        return best
    }

    private static func readLatestRate(from url: URL, size: UInt64, fallbackDate: Date) -> RateLimit? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Scan backwards in bounded chunks: a large tool response can push the
        // last rate event well beyond the old 100KB tail. Keep split UTF-8/JSON
        // bytes until the complete line is available.
        var offset = size
        let lowerBound = size > maxScanBytes ? size - maxScanBytes : 0
        var pending = Data()
        while offset > lowerBound {
            let count = Int(min(64 * 1024, offset - lowerBound))
            offset -= UInt64(count)
            do {
                try handle.seek(toOffset: offset)
                guard let chunk = try handle.read(upToCount: count), chunk.count == count else { return nil }
                pending.insert(contentsOf: chunk, at: pending.startIndex)
            } catch { return nil }
            while let newline = pending.lastIndex(of: 0x0A) {
                let line = pending[pending.index(after: newline)...]
                if let rate = parseRateLine(Data(line), fallbackDate: fallbackDate) { return rate }
                pending.removeSubrange(newline...)
            }
        }
        return lowerBound == 0 ? parseRateLine(pending, fallbackDate: fallbackDate) : nil
    }

    private static func parseRateLine(_ data: Data, fallbackDate: Date) -> RateLimit? {
        guard let text = String(data: data, encoding: .utf8),
              text.contains("rate_limits"), text.contains("used_percent"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let payload = json["payload"] as? [String: Any]
        guard let rl = (json["rate_limits"] ?? payload?["rate_limits"]) as? [String: Any],
              (rl["limit_id"] as? String ?? "codex") == "codex" else { return nil }

        var fiveHour: (Double, Date?)?
        var sevenDay: (Double, Date?)?
        for (name, defaultMinutes) in [("primary", 300), ("secondary", 10_080)] {
            guard let raw = rl[name] as? [String: Any],
                  let pct = raw["used_percent"] as? Double,
                  pct.isFinite, (0...100).contains(pct) else { continue }
            let minutes = (raw["window_minutes"] as? NSNumber)?.intValue ?? defaultMinutes
            let reset = (raw["resets_at"] as? Double).flatMap { $0.isFinite ? normalizeTimestamp($0) : nil }
            if minutes == 300 { fiveHour = (pct, reset) }
            if minutes == 10_080 { sevenDay = (pct, reset) }
        }
        guard fiveHour != nil || sevenDay != nil else { return nil }
        let timestamp = (json["timestamp"] as? String).flatMap { isoFull.date(from: $0) ?? isoBasic.date(from: $0) }
        return RateLimit(fiveHourPct: fiveHour?.0, sevenDayPct: sevenDay?.0,
                         fiveHourResetsAt: fiveHour?.1, sevenDayResetsAt: sevenDay?.1,
                         updatedAt: timestamp ?? fallbackDate)
    }

    private static func recentRollouts(in dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [(URL, Date)] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl",
                  let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            else { continue }
            files.append((url, mod))
        }
        return files.sorted {
            $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 > $1.1
        }.prefix(maxCandidates).map { $0.0 }
    }
}

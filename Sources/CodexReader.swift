import Foundation

enum CodexReader {
    struct UsageEntry: Equatable, Hashable {
        let id: String
        let sessionID: String
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
        let reasoningOutputTokens: Int
        let totalTokens: Int
        var cacheWriteInputTokens: Int = 0
        var serviceTier: String? = nil

        private var billableCachedInputTokens: Int {
            min(inputTokens, cachedInputTokens)
        }

        private var billableInputTokens: Int {
            max(0, inputTokens - billableCachedInputTokens - billableCacheWriteTokens)
        }

        private var billableCacheWriteTokens: Int {
            min(max(0, inputTokens - billableCachedInputTokens), max(0, cacheWriteInputTokens))
        }

        var cost: Double {
            Pricing.cost(
                model: model,
                serviceTier: serviceTier,
                at: timestamp,
                input: billableInputTokens,
                output: outputTokens,
                cacheWrite: billableCacheWriteTokens,
                cacheRead: billableCachedInputTokens
            )
        }

        var hasKnownCost: Bool {
            Pricing.hasRate(model: model, serviceTier: serviceTier)
        }
    }

    private struct RawUsage {
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
        let reasoningOutputTokens: Int
        let totalTokens: Int
        let cacheWriteInputTokens: Int
    }

    private struct ParserState {
        var sessionID: String
        var currentModel: String?
        var previousTotal: RawUsage?
        var serviceTier: String?
        var hasResponseRecords: Bool
    }

    private struct ParsedSession {
        let entries: [UsageEntry]
        let state: ParserState
        let trailingData: Data
        let discardingLine: Bool
    }

    private struct CachedSessionFile {
        let mod: Date
        let size: Int
        let fileID: UInt64?
        let entries: [UsageEntry]
        let state: ParserState
        let trailingData: Data
        let discardingLine: Bool
    }

    private static var defaultSessionsDir: URL { AppPaths.codexSessionsDir }

    private static let cacheLock = NSLock()
    private static var fileCacheBySessionsDir: [String: [String: CachedSessionFile]] = [:]

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Read per-event Codex usage deltas since `cutoff` from session JSONL files.
    /// Returns `nil` on parse/enumeration failure so the caller can keep the
    /// previous snapshot instead of flickering the UI to empty.
    static func readEntries(since cutoff: Date) -> [UsageEntry]? {
        readEntries(since: cutoff, sessionsDir: defaultSessionsDir)
    }

    static func readEntries(since cutoff: Date, sessionsDir: URL, archivedSessionsDir: URL? = nil) -> [UsageEntry]? {
        let archive = archivedSessionsDir ?? sessionsDir.deletingLastPathComponent()
            .appendingPathComponent("archived_sessions", isDirectory: true)
        let roots = [sessionsDir, archive]
        let cacheKey = roots.map { $0.standardizedFileURL.path }.joined(separator: "\n")
        let cacheSnapshot = cachedFiles(for: cacheKey)
        var newCache: [String: CachedSessionFile] = [:]
        var results: [UsageEntry] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return nil }
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl" else { continue }

                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mod = values.contentModificationDate,
                      let size = values.fileSize
                else {
                    return nil
                }

                if mod < cutoff {
                    continue
                }
                let path = url.path
                let fileID = fileID(for: url)
                let cached = cacheSnapshot[path]

                if let cached,
                   cached.mod == mod,
                   cached.size == size,
                   cached.fileID == fileID {
                    let entries = cached.entries.filter { $0.timestamp >= cutoff }
                    newCache[path] = CachedSessionFile(
                        mod: cached.mod,
                        size: cached.size,
                        fileID: cached.fileID,
                        entries: entries,
                        state: cached.state,
                        trailingData: cached.trailingData,
                        discardingLine: cached.discardingLine
                    )
                    results.append(contentsOf: entries)
                    continue
                }

                let parsed: ParsedSession
                let entries: [UsageEntry]

                if let cached,
                   cached.fileID != nil,
                   cached.fileID == fileID,
                   size > cached.size {
                    guard let incremental = parseSessionFile(
                        url,
                        cutoff: cutoff,
                        fromOffset: cached.size,
                        carryover: cached.trailingData,
                        discardingLine: cached.discardingLine,
                        initialState: cached.state,
                        throughOffset: size
                    ) else {
                        return nil
                    }
                    parsed = incremental
                    entries = (cached.entries + incremental.entries).filter { $0.timestamp >= cutoff }
                } else {
                    guard let full = parseSessionFile(url, cutoff: cutoff, throughOffset: size) else {
                        return nil
                    }
                    parsed = full
                    entries = full.entries.filter { $0.timestamp >= cutoff }
                }

                newCache[path] = CachedSessionFile(
                    mod: mod,
                    size: size,
                    fileID: fileID,
                    entries: entries,
                    state: parsed.state,
                    trailingData: parsed.trailingData,
                    discardingLine: parsed.discardingLine
                )
                results.append(contentsOf: entries)
            }

        }
        storeCachedFiles(newCache, for: cacheKey)
        // Forked histories and files moved between active/archive directories
        // can contain the same response. Its provider ID is stable across copies.
        var unique: [String: UsageEntry] = [:]
        for entry in results {
            if let prior = unique[entry.id], prior.totalTokens >= entry.totalTokens { continue }
            unique[entry.id] = entry
        }
        return unique.values.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp { return lhs.id < rhs.id }
            return lhs.timestamp < rhs.timestamp
        }
    }

    private static func parseSessionFile(
        _ url: URL,
        cutoff: Date,
        fromOffset offset: Int = 0,
        carryover: Data = Data(),
        discardingLine: Bool = false,
        initialState: ParserState? = nil,
        throughOffset endOffset: Int
    ) -> ParsedSession? {
        var state = initialState ?? initialStateFor(url)
        var entries: [UsageEntry] = []
        guard let result = JSONLStreamReader.read(
            url, fromOffset: offset, throughOffset: endOffset,
            carryover: carryover, discardingLine: discardingLine,
            onObject: { json in
                _ = drainObject(json, cutoff: cutoff, state: &state, into: &entries)
            }
        ) else { return nil }
        return ParsedSession(entries: entries, state: state,
                             trailingData: result.trailingData, discardingLine: result.discardingLine)
    }

    private static func drainObject(
        _ json: [String: Any],
        cutoff: Date,
        state: inout ParserState,
        into entries: inout [UsageEntry]
    ) -> Bool {
        guard let type = json["type"] as? String else { return false }

        let payload = json["payload"] as? [String: Any] ?? [:]

        if type == "session_meta", let id = nonEmptyString(payload["id"]) {
            state.sessionID = id
            return true
        }

        if type == "turn_context", let model = nonEmptyString(payload["model"]) {
            if model != state.currentModel { state.serviceTier = nil }
            state.currentModel = model
            if payload.keys.contains("service_tier") {
                state.serviceTier = nonEmptyString(payload["service_tier"])
            }
            return true
        }

        if type == "event_msg", payload["type"] as? String == "thread_settings_applied",
           let settings = payload["thread_settings"] as? [String: Any],
           let model = nonEmptyString(settings["model"]) {
            // Forked histories may contain snapshots owned by the parent.
            if let owner = nonEmptyString(payload["thread_id"]), owner != state.sessionID { return true }
            state.currentModel = model
            state.serviceTier = nonEmptyString(settings["service_tier"])
            return true
        }

        if type == "token_usage_record",
           let responseID = nonEmptyString(payload["response_id"]),
           let raw = normalizeUsage(payload["usage"]),
           let timestampText = json["timestamp"] as? String,
           let timestamp = parseDate(timestampText) {
            // These are exact per-response deltas. The subsequent token_count
            // is a delayed UI snapshot of the same work, and may coalesce several
            // responses into one last_token_usage. Never add both streams.
            state.hasResponseRecords = true
            guard timestamp >= cutoff else { return true }
            let owner = nonEmptyString(payload["thread_id"]) ?? state.sessionID
            entries.append(UsageEntry(
                id: "response:\(owner):\(responseID)", sessionID: owner,
                timestamp: timestamp, model: state.currentModel ?? "unknown",
                inputTokens: raw.inputTokens, cachedInputTokens: raw.cachedInputTokens,
                outputTokens: raw.outputTokens, reasoningOutputTokens: raw.reasoningOutputTokens,
                totalTokens: raw.totalTokens, cacheWriteInputTokens: raw.cacheWriteInputTokens,
                serviceTier: state.serviceTier
            ))
            return true
        }

        guard !state.hasResponseRecords,
              type == "event_msg",
              payload["type"] as? String == "token_count",
              let timestampText = json["timestamp"] as? String,
              let timestamp = parseDate(timestampText)
        else { return true }

        if let model = extractModel(from: payload) {
            if model != state.currentModel { state.serviceTier = nil }
            state.currentModel = model
        }

        let info = payload["info"] as? [String: Any] ?? [:]
        let totalRaw = normalizeUsage(info["total_token_usage"])
        let totalDelta = totalRaw.map {
            subtractUsage(current: $0, previous: state.previousTotal)
        }
        let deltaRaw: RawUsage?

        if let lastRaw = normalizeUsage(info["last_token_usage"]),
           totalDelta?.totalTokens != 0 {
            deltaRaw = lastRaw
        } else if let totalDelta {
            deltaRaw = totalDelta
        } else {
            deltaRaw = nil
        }

        if let totalRaw {
            state.previousTotal = totalRaw
        }

        guard timestamp >= cutoff else { return true }
        guard let deltaRaw,
              let model = state.currentModel,
              deltaRaw.totalTokens > 0
        else { return true }

        entries.append(
            UsageEntry(
                id: "legacy:\(state.sessionID):\(timestampText):\(totalRaw?.totalTokens ?? deltaRaw.totalTokens)",
                sessionID: state.sessionID,
                timestamp: timestamp,
                model: model,
                inputTokens: deltaRaw.inputTokens,
                cachedInputTokens: deltaRaw.cachedInputTokens,
                outputTokens: deltaRaw.outputTokens,
                reasoningOutputTokens: deltaRaw.reasoningOutputTokens,
                totalTokens: deltaRaw.totalTokens,
                cacheWriteInputTokens: deltaRaw.cacheWriteInputTokens,
                serviceTier: state.serviceTier
            )
        )
        return true
    }

    private static func cachedFiles(for key: String) -> [String: CachedSessionFile] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return fileCacheBySessionsDir[key] ?? [:]
    }

    private static func storeCachedFiles(_ files: [String: CachedSessionFile], for key: String) {
        cacheLock.lock()
        fileCacheBySessionsDir[key] = files
        cacheLock.unlock()
    }

    private static func initialStateFor(_ url: URL) -> ParserState {
        ParserState(
            sessionID: url.deletingPathExtension().lastPathComponent,
            currentModel: nil,
            previousTotal: nil,
            serviceTier: nil,
            hasResponseRecords: false
        )
    }

    private static func fileID(for url: URL) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let raw = attrs[.systemFileNumber] as? NSNumber else {
            return nil
        }
        return raw.uint64Value
    }

    private static func normalizeUsage(_ raw: Any?) -> RawUsage? {
        guard let dict = raw as? [String: Any] else { return nil }

        guard let input = intValue(dict["input_tokens"]),
              let cached = intValue(dict["cached_input_tokens"] ?? dict["cache_read_input_tokens"]),
              let output = intValue(dict["output_tokens"]),
              let reasoning = intValue(dict["reasoning_output_tokens"]),
              let explicitTotal = intValue(dict["total_tokens"]),
              let cacheWrite = intValue(dict["cache_write_input_tokens"])
        else { return nil }
        let (componentTotal, overflow) = input.addingReportingOverflow(output)
        guard !overflow else { return nil }
        let total = explicitTotal > 0 ? explicitTotal : componentTotal

        if input == 0, cached == 0, output == 0, reasoning == 0, total == 0 {
            return nil
        }

        return RawUsage(
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningOutputTokens: reasoning,
            totalTokens: total,
            cacheWriteInputTokens: cacheWrite
        )
    }

    private static func subtractUsage(current: RawUsage, previous: RawUsage?) -> RawUsage {
        // A restarted cumulative counter begins a new baseline; clamping the
        // negative difference to zero would discard the first new request.
        if let previous, current.totalTokens < previous.totalTokens { return current }
        return RawUsage(
            inputTokens: max(0, current.inputTokens - (previous?.inputTokens ?? 0)),
            cachedInputTokens: max(0, current.cachedInputTokens - (previous?.cachedInputTokens ?? 0)),
            outputTokens: max(0, current.outputTokens - (previous?.outputTokens ?? 0)),
            reasoningOutputTokens: max(0, current.reasoningOutputTokens - (previous?.reasoningOutputTokens ?? 0)),
            totalTokens: max(0, current.totalTokens - (previous?.totalTokens ?? 0)),
            cacheWriteInputTokens: max(0, current.cacheWriteInputTokens - (previous?.cacheWriteInputTokens ?? 0))
        )
    }

    private static func extractModel(from payload: [String: Any]) -> String? {
        if let info = payload["info"] as? [String: Any] {
            if let model = nonEmptyString(info["model"]) ?? nonEmptyString(info["model_name"]) {
                return model
            }
            if let metadata = info["metadata"] as? [String: Any],
               let model = nonEmptyString(metadata["model"]) {
                return model
            }
        }

        if let model = nonEmptyString(payload["model"]) {
            return model
        }
        if let metadata = payload["metadata"] as? [String: Any],
           let model = nonEmptyString(metadata["model"]) {
            return model
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = JSONLStreamReader.detachedString(value) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(_ value: Any?) -> Int? {
        guard let value else { return 0 }
        let integer: Int?
        switch value {
        case let n as Int:
            integer = n
        case let n as Int64:
            integer = Int(exactly: n)
        case let n as Double:
            integer = Int(exactly: n)
        case let n as NSNumber:
            integer = Int(exactly: n.doubleValue)
        default:
            return nil
        }
        guard let integer, integer >= 0 else { return nil }
        return integer
    }

    private static func parseDate(_ text: String) -> Date? {
        isoFull.date(from: text) ?? isoBasic.date(from: text)
    }

    static func shortenModel(_ model: String) -> String {
        model.isEmpty ? "unknown" : model
    }
}

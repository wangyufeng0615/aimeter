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

        private var billableCachedInputTokens: Int {
            min(inputTokens, cachedInputTokens)
        }

        private var billableInputTokens: Int {
            max(0, inputTokens - billableCachedInputTokens)
        }

        var cost: Double {
            Pricing.cost(
                model: model,
                input: billableInputTokens,
                output: outputTokens,
                cacheWrite: 0,
                cacheRead: billableCachedInputTokens
            )
        }
    }

    private struct RawUsage {
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
        let reasoningOutputTokens: Int
        let totalTokens: Int
    }

    private static let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")

    /// Hard cap matching UsageStore.maxFileBytes — skip pathological session
    /// files rather than risk OOM when accumulating the decode buffer.
    private static let maxFileBytes: Int = 64 * 1024 * 1024

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
        readEntries(since: cutoff, sessionsDir: sessionsDir)
    }

    static func readEntries(since cutoff: Date, sessionsDir: URL) -> [UsageEntry]? {
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else { return [] }

        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var results: [UsageEntry] = []

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }

            let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let mod, mod < cutoff {
                continue
            }

            guard let fileEntries = parseSessionFile(url, cutoff: cutoff) else {
                return nil
            }
            results.append(contentsOf: fileEntries)
        }

        return results.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp { return lhs.id < rhs.id }
            return lhs.timestamp < rhs.timestamp
        }
    }

    private static func parseSessionFile(_ url: URL, cutoff: Date) -> [UsageEntry]? {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           size > maxFileBytes {
            // Skip oversized sessions silently — returning an empty array
            // (not nil) signals a non-error skip so the caller keeps
            // processing other files.
            return []
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var buffer = Data()
        var sessionID = url.deletingPathExtension().lastPathComponent
        var currentModel: String?
        var previousTotal: RawUsage?
        var sequence = 0
        var entries: [UsageEntry] = []

        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            buffer.append(chunk)
            drainLines(
                from: &buffer,
                cutoff: cutoff,
                sessionID: &sessionID,
                currentModel: &currentModel,
                previousTotal: &previousTotal,
                sequence: &sequence,
                into: &entries
            )
        }

        if !buffer.isEmpty {
            drainLine(
                String(decoding: buffer, as: UTF8.self),
                cutoff: cutoff,
                sessionID: &sessionID,
                currentModel: &currentModel,
                previousTotal: &previousTotal,
                sequence: &sequence,
                into: &entries
            )
        }

        return entries
    }

    private static func drainLines(
        from buffer: inout Data,
        cutoff: Date,
        sessionID: inout String,
        currentModel: inout String?,
        previousTotal: inout RawUsage?,
        sequence: inout Int,
        into entries: inout [UsageEntry]
    ) {
        var nextStart = buffer.startIndex

        while nextStart < buffer.endIndex,
              let newline = buffer[nextStart...].firstIndex(of: 0x0A) {
            let lineData = buffer[nextStart..<newline]
            nextStart = buffer.index(after: newline)
            drainLine(
                String(decoding: lineData, as: UTF8.self),
                cutoff: cutoff,
                sessionID: &sessionID,
                currentModel: &currentModel,
                previousTotal: &previousTotal,
                sequence: &sequence,
                into: &entries
            )
        }

        if nextStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<nextStart)
        }
    }

    private static func drainLine(
        _ line: String,
        cutoff: Date,
        sessionID: inout String,
        currentModel: inout String?,
        previousTotal: inout RawUsage?,
        sequence: inout Int,
        into entries: inout [UsageEntry]
    ) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        let payload = json["payload"] as? [String: Any] ?? [:]

        if type == "session_meta", let id = payload["id"] as? String, !id.isEmpty {
            sessionID = id
            return
        }

        if type == "turn_context", let model = payload["model"] as? String, !model.isEmpty {
            currentModel = model
            return
        }

        guard type == "event_msg",
              payload["type"] as? String == "token_count",
              let timestampText = json["timestamp"] as? String,
              let timestamp = parseDate(timestampText)
        else { return }

        guard timestamp >= cutoff else { return }

        if let model = extractModel(from: payload) {
            currentModel = model
        }

        let info = payload["info"] as? [String: Any] ?? [:]
        let totalRaw = normalizeUsage(info["total_token_usage"])
        let deltaRaw: RawUsage?

        if let lastRaw = normalizeUsage(info["last_token_usage"]) {
            deltaRaw = lastRaw
        } else if let totalRaw {
            deltaRaw = subtractUsage(current: totalRaw, previous: previousTotal)
        } else {
            deltaRaw = nil
        }

        if let totalRaw {
            previousTotal = totalRaw
        }

        guard let deltaRaw,
              let model = currentModel,
              deltaRaw.totalTokens > 0
        else { return }

        sequence += 1
        entries.append(
            UsageEntry(
                id: "\(sessionID):\(sequence)",
                sessionID: sessionID,
                timestamp: timestamp,
                model: model,
                inputTokens: deltaRaw.inputTokens,
                cachedInputTokens: deltaRaw.cachedInputTokens,
                outputTokens: deltaRaw.outputTokens,
                reasoningOutputTokens: deltaRaw.reasoningOutputTokens,
                totalTokens: deltaRaw.totalTokens
            )
        )
    }

    private static func normalizeUsage(_ raw: Any?) -> RawUsage? {
        guard let dict = raw as? [String: Any] else { return nil }

        let input = intValue(dict["input_tokens"])
        let cached = intValue(dict["cached_input_tokens"] ?? dict["cache_read_input_tokens"])
        let output = intValue(dict["output_tokens"])
        let reasoning = intValue(dict["reasoning_output_tokens"])
        let explicitTotal = intValue(dict["total_tokens"])
        let total = explicitTotal > 0 ? explicitTotal : input + output

        if input == 0, cached == 0, output == 0, reasoning == 0, total == 0 {
            return nil
        }

        return RawUsage(
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningOutputTokens: reasoning,
            totalTokens: total
        )
    }

    private static func subtractUsage(current: RawUsage, previous: RawUsage?) -> RawUsage {
        RawUsage(
            inputTokens: max(0, current.inputTokens - (previous?.inputTokens ?? 0)),
            cachedInputTokens: max(0, current.cachedInputTokens - (previous?.cachedInputTokens ?? 0)),
            outputTokens: max(0, current.outputTokens - (previous?.outputTokens ?? 0)),
            reasoningOutputTokens: max(0, current.reasoningOutputTokens - (previous?.reasoningOutputTokens ?? 0)),
            totalTokens: max(0, current.totalTokens - (previous?.totalTokens ?? 0))
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
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let n as Int:
            return n
        case let n as Int64:
            return Int(n)
        case let n as Double:
            return Int(n)
        case let n as NSNumber:
            return n.intValue
        default:
            return 0
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        isoFull.date(from: text) ?? isoBasic.date(from: text)
    }

    static func shortenModel(_ model: String) -> String {
        model.isEmpty ? "unknown" : model
    }
}

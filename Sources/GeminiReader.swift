import Foundation
import SQLite3

/// Local Google agent usage: Antigravity (IDE and CLI) conversation databases
/// plus Gemini CLI chat recordings. Both normalize into `UsageEntry` with
/// uncached input, cache reads and output (thinking included) kept separate
/// so token totals never double-count cached prompt tokens.
final class GeminiReader {
    private struct FileSignature: Equatable {
        let size: Int
        let modified: Date
        let walSize: Int
        let walModified: Date?
    }

    private struct CachedFile {
        let signature: FileSignature
        let entries: [UsageEntry]
    }

    static let shared = GeminiReader()

    private let lock = NSLock()
    private var cache: [String: CachedFile] = [:]
    private var cachedRoot: URL?

    /// Thread-safe; Stage 2 calls it from a background queue.
    func readEntries(cutoff: Date) -> [UsageEntry] {
        readEntries(
            antigravityConversationDirs: AppPaths.antigravityConversationDirs,
            geminiCLITmpDir: AppPaths.geminiCLITmpDir,
            root: AppPaths.geminiRoot,
            cutoff: cutoff
        )
    }

    func readEntries(antigravityConversationDirs: [URL], geminiCLITmpDir: URL,
                     root: URL? = nil, cutoff: Date) -> [UsageEntry] {
        lock.lock()
        defer { lock.unlock() }
        if cachedRoot != root {
            cache = [:]
            cachedRoot = root
        }

        var nextCache: [String: CachedFile] = [:]
        var byID: [String: UsageEntry] = [:]

        func collect(_ url: URL, parse: (URL) -> [UsageEntry]?) {
            guard let signature = Self.signature(for: url),
                  max(signature.modified, signature.walModified ?? .distantPast) >= cutoff else { return }
            let cached = cache[url.path]
            if let cached, cached.signature == signature {
                nextCache[url.path] = cached
            } else if let parsed = parse(url) {
                nextCache[url.path] = CachedFile(signature: signature, entries: parsed)
            } else if let cached {
                // A busy or mid-write database keeps its last parse; the stale
                // signature makes the next refresh try again.
                nextCache[url.path] = cached
            } else {
                return
            }
            let entries = nextCache[url.path]?.entries ?? []
            for entry in entries where entry.timestamp >= cutoff {
                // Subagent and resumed trajectories can copy a generation;
                // the provider response ID identifies the billed call.
                if byID[entry.id] == nil { byID[entry.id] = entry }
            }
        }

        let fm = FileManager.default
        for dir in antigravityConversationDirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in files where url.pathExtension == "db" {
                collect(url, parse: Self.parseAntigravityDatabase)
            }
        }

        if let projects = try? fm.contentsOfDirectory(at: geminiCLITmpDir, includingPropertiesForKeys: nil) {
            for project in projects {
                let chats = project.appendingPathComponent("chats", isDirectory: true)
                guard let files = try? fm.contentsOfDirectory(at: chats, includingPropertiesForKeys: nil) else { continue }
                for url in files where url.lastPathComponent.hasPrefix("session-") && url.pathExtension == "json" {
                    collect(url, parse: Self.parseGeminiCLISession)
                }
            }
        }

        cache = nextCache
        return byID.values.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Antigravity

    /// `gen_metadata.data` is a CortexStepGeneratorMetadata blob:
    ///   1: ChatModelMetadata { 4: ModelUsageStats usage, 19: response_model,
    ///      20: custom_metadata (key/value), 21: model_display_name }
    ///   2: packed indices of the steps this generation produced
    /// ModelUsageStats: 2 input (uncached), 3 output (thinking included),
    /// 4 cache write, 5 cache read, 7 message_id, 11 response_id.
    /// Steps carry the wall-clock time in CortexStepMetadata.created_at (1).
    static func parseAntigravityDatabase(_ url: URL) -> [UsageEntry]? {
        // A closed conversation keeps WAL journal mode but has no -shm/-wal
        // files. The system SQLite cannot create the shared-memory file on a
        // read-only connection, and there is no pending WAL content to read,
        // so the file is opened as immutable in exactly that state.
        let fm = FileManager.default
        let walSize = (try? fm.attributesOfItem(atPath: url.path + "-wal"))?[.size] as? NSNumber
        let isQuiescent = !fm.fileExists(atPath: url.path + "-shm") && (walSize?.intValue ?? 0) == 0
        let target = isQuiescent ? url.absoluteString + "?immutable=1" : url.path
        var db: OpaquePointer?
        guard sqlite3_open_v2(target, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        var stepTimes: [Int: Date] = [:]
        guard query(db, "SELECT idx, metadata FROM steps", { statement in
            let index = Int(sqlite3_column_int64(statement, 0))
            if let data = blob(statement, 1),
               let date = ProtobufMessage(data)?.timestamp(1) {
                stepTimes[index] = date
            }
        }) else { return nil }

        let conversation = url.deletingPathExtension().lastPathComponent
        var entries: [UsageEntry] = []
        guard query(db, "SELECT idx, data FROM gen_metadata", { statement in
            let index = Int(sqlite3_column_int64(statement, 0))
            guard let data = blob(statement, 1),
                  let generation = ProtobufMessage(data),
                  let chat = generation.message(1),
                  let usage = chat.message(4) else { return }

            let input = usage.int(2)
            let output = usage.int(3)
            let cacheWrite = usage.int(4)
            let cacheRead = usage.int(5)
            guard input + output + cacheWrite + cacheRead > 0 else { return }

            // A generation is timestamped by the first step it produced. Failed
            // generations produce no step; they still bill tokens and record
            // the step they followed in custom metadata.
            var metadata: [String: String] = [:]
            for pair in chat.allMessages(20) {
                if let key = pair.string(1), let value = pair.string(2) { metadata[key] = value }
            }
            let producedStep = generation.packedVarints(2).first.map { Int(clamping: $0) }
            let previousStep = metadata["last_step_index"].flatMap(Int.init)
            guard let timestamp = producedStep.flatMap({ stepTimes[$0] })
                    ?? previousStep.flatMap({ stepTimes[$0] }) else { return }

            let model = normalizedAntigravityModel(
                chat.string(19) ?? "",
                displayName: chat.string(21) ?? ""
            )
            // Third-party models (Claude, GPT-OSS) inside Antigravity are not
            // tracked; only Gemini usage is shown for Google agents.
            guard model.hasPrefix("gemini") else { return }
            let responseID = [usage.string(11), usage.string(7)]
                .compactMap { $0 }
                .first { !$0.isEmpty }
            entries.append(UsageEntry(
                id: responseID.map { "antigravity:\($0)" } ?? "antigravity:\(conversation):\(index)",
                timestamp: timestamp,
                model: model,
                inputTokens: input,
                outputTokens: output,
                cacheCreationTokens: cacheWrite,
                cacheCreation1hTokens: 0,
                cacheReadTokens: cacheRead,
                speed: nil,
                inferenceGeo: nil,
                costUSD: nil
            ))
        }) else { return nil }
        return entries
    }

    /// Generations normally carry the response model ID; fall back to the
    /// display name ("Gemini 4 Neon (High)" → "gemini-4-neon") when absent.
    static func normalizedAntigravityModel(_ raw: String, displayName: String) -> String {
        let model = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.isEmpty else { return model }
        return displayName.lowercased()
            .replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func query(_ db: OpaquePointer, _ sql: String,
                              _ row: (OpaquePointer) -> Void) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: row(statement)
            case SQLITE_DONE: return true
            default: return false
            }
        }
    }

    private static func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        let length = Int(sqlite3_column_bytes(statement, column))
        guard length > 0, let pointer = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: pointer, count: length)
    }

    // MARK: - Gemini CLI

    /// Gemini CLI records `messages[]`; model turns (`type == "gemini"`) carry
    /// Gemini API counts where `input` includes `cached` and `output` excludes
    /// `thoughts`.
    static func parseGeminiCLISession(_ url: URL) -> [UsageEntry]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return nil }
        let session = json["sessionId"] as? String ?? url.deletingPathExtension().lastPathComponent

        return messages.enumerated().compactMap { offset, message in
            guard message["type"] as? String == "gemini",
                  let tokens = message["tokens"] as? [String: Any],
                  let timestamp = (message["timestamp"] as? String).flatMap(parseDate) else { return nil }
            func count(_ key: String) -> Int { max(0, (tokens[key] as? NSNumber)?.intValue ?? 0) }
            let cached = min(count("input"), count("cached"))
            let input = count("input") - cached
            let output = count("output") + count("thoughts")
            guard input + output + cached > 0 else { return nil }
            let messageID = message["id"] as? String ?? String(offset)
            return UsageEntry(
                id: "gemini-cli:\(session):\(messageID)",
                timestamp: timestamp,
                model: (message["model"] as? String ?? "gemini").lowercased(),
                inputTokens: input,
                outputTokens: output,
                cacheCreationTokens: 0,
                cacheCreation1hTokens: 0,
                cacheReadTokens: cached,
                speed: nil,
                inferenceGeo: nil,
                costUSD: nil
            )
        }
    }

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoBasic = ISO8601DateFormatter()

    private static func parseDate(_ value: String) -> Date? {
        isoFull.date(from: value) ?? isoBasic.date(from: value)
    }

    // MARK: - Files

    private static func signature(for url: URL) -> FileSignature? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        // SQLite writes land in the WAL first; its change must invalidate
        // the cached parse even while the main database file is untouched.
        let wal = try? fm.attributesOfItem(atPath: url.path + "-wal")
        return FileSignature(
            size: size,
            modified: modified,
            walSize: (wal?[.size] as? NSNumber)?.intValue ?? 0,
            walModified: wal?[.modificationDate] as? Date
        )
    }
}

import Foundation
import SQLite3
import XCTest
@testable import AIMeter

final class GeminiReaderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aimeter-gemini-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if tempDir != nil { try? FileManager.default.removeItem(at: tempDir) }
        tempDir = nil
    }

    // MARK: - Protobuf

    func testProtobufReadsNestedPackedAndUnknownFields() throws {
        let w = PB()
            .varint(1, 300)
            .bytes(2, PB().varint(1, 7).varint(2, 9).data)
            .packed(3, [1, 128, 70000])
            .fixed64(4, 42)
            .string(5, "héllo")
        let message = try XCTUnwrap(ProtobufMessage(w.data))
        XCTAssertEqual(message.varint(1), 300)
        XCTAssertEqual(message.message(2)?.int(2), 9)
        XCTAssertEqual(message.packedVarints(3), [1, 128, 70000])
        XCTAssertEqual(message.string(5), "héllo")
        XCTAssertNil(ProtobufMessage(Data([0x0a, 0x05, 0x01])), "truncated length must fail")
    }

    // MARK: - Antigravity

    func testAntigravityGenerationsUseProducedStepTimeAndSeparateCacheTokens() throws {
        let dir = tempDir.appendingPathComponent("antigravity/conversations", isDirectory: true)
        let stepTime = Date(timeIntervalSince1970: 1_795_684_959)
        let failedTime = Date(timeIntervalSince1970: 1_795_685_100)
        try makeDatabase(at: dir.appendingPathComponent("a.db"), steps: [
            (377, stepTime.addingTimeInterval(-30)),
            (378, stepTime),
            (400, failedTime),
        ], generations: [
            (90, generation(model: "gemini-4-neon", display: "Gemini 4 Neon (High)",
                            input: 2369, output: 2163, cacheRead: 58806, responseID: "r1",
                            producedSteps: [378, 379], lastStep: 377)),
            // Failed request: no produced step, still billed.
            (91, generation(model: "claude-opus-5-5-medium", display: "Claude Opus 5.5 (Medium)",
                            input: 1000, output: 20, cacheRead: 0, responseID: "r2",
                            producedSteps: [], lastStep: 400)),
            // 429 without usage is ignored.
            (92, generation(model: "gemini-4-neon", display: "Gemini 4 Neon (High)",
                            input: 0, output: 0, cacheRead: 0, responseID: "",
                            producedSteps: [], lastStep: 400)),
        ])

        let entries = GeminiReader().readEntries(
            antigravityConversationDirs: [dir],
            geminiCLITmpDir: tempDir.appendingPathComponent("tmp"),
            cutoff: stepTime.addingTimeInterval(-86400)
        )

        XCTAssertEqual(entries.count, 2)
        for suffix in ["-shm", "-wal"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.db" + suffix).path),
                           "reading a closed WAL database must not create SQLite side files")
        }
        let neon = try XCTUnwrap(entries.first { $0.model == "gemini-4-neon" })
        XCTAssertEqual(neon.timestamp, stepTime)
        XCTAssertEqual(neon.inputTokens, 2369)
        XCTAssertEqual(neon.outputTokens, 2163)
        XCTAssertEqual(neon.cacheReadTokens, 58806)
        XCTAssertEqual(neon.totalTokens, 2369 + 2163 + 58806)
        XCTAssertFalse(neon.hasKnownCost)

        let opus = try XCTUnwrap(entries.first { $0.model == "claude-opus-5-5" },
                                 "effort suffix is stripped so Claude rates apply")
        XCTAssertEqual(opus.timestamp, failedTime)
        XCTAssertTrue(opus.hasKnownCost)
    }

    func testAntigravityDeduplicatesAcrossDatabasesAndRereadsChangedFiles() throws {
        let ide = tempDir.appendingPathComponent("antigravity/conversations", isDirectory: true)
        let cli = tempDir.appendingPathComponent("antigravity-cli/conversations", isDirectory: true)
        let time = Date()
        let shared = generation(model: "gemini-4-neon", display: "", input: 10, output: 5, cacheRead: 0,
                                responseID: "same", producedSteps: [1], lastStep: 0)
        try makeDatabase(at: ide.appendingPathComponent("a.db"), steps: [(1, time)], generations: [(0, shared)])
        try makeDatabase(at: cli.appendingPathComponent("b.db"), steps: [(1, time)], generations: [(0, shared)])

        let reader = GeminiReader()
        let tmp = tempDir.appendingPathComponent("tmp")
        let cutoff = time.addingTimeInterval(-3600)
        XCTAssertEqual(reader.readEntries(antigravityConversationDirs: [ide, cli],
                                          geminiCLITmpDir: tmp, cutoff: cutoff).count, 1)

        try insertGeneration(into: ide.appendingPathComponent("a.db"), index: 1, data: generation(
            model: "gemini-4-neon", display: "", input: 1, output: 1, cacheRead: 0,
            responseID: "new", producedSteps: [1], lastStep: 0))
        let entries = reader.readEntries(antigravityConversationDirs: [ide, cli],
                                         geminiCLITmpDir: tmp, cutoff: cutoff)
        XCTAssertEqual(entries.map(\.totalTokens).sorted(), [2, 15])
    }

    func testUnreadableDatabaseKeepsLastParse() throws {
        let dir = tempDir.appendingPathComponent("antigravity/conversations", isDirectory: true)
        let db = dir.appendingPathComponent("a.db")
        let time = Date()
        try makeDatabase(at: db, steps: [(1, time)], generations: [(0, generation(
            model: "gemini-4-neon", display: "", input: 10, output: 5, cacheRead: 0,
            responseID: "r", producedSteps: [1], lastStep: 0))])
        let reader = GeminiReader()
        let tmp = tempDir.appendingPathComponent("tmp")
        XCTAssertEqual(reader.readEntries(antigravityConversationDirs: [dir], geminiCLITmpDir: tmp,
                                          cutoff: time.addingTimeInterval(-60)).count, 1)
        try Data("not a database".utf8).write(to: db)
        XCTAssertEqual(reader.readEntries(antigravityConversationDirs: [dir], geminiCLITmpDir: tmp,
                                          cutoff: time.addingTimeInterval(-60)).count, 1)
    }

    // MARK: - Gemini CLI

    func testGeminiCLIConvertsInclusiveInputAndExclusiveThoughts() throws {
        let chats = tempDir.appendingPathComponent("tmp/abc/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        let json = """
        {"sessionId":"s1","messages":[
          {"id":"u","type":"user","timestamp":"2026-11-26T06:20:00.000Z","content":"hi"},
          {"id":"g","type":"gemini","timestamp":"2026-11-26T06:20:49.941Z","model":"gemini-3-flash-preview",
           "tokens":{"input":7601,"output":27,"cached":3104,"thoughts":238,"tool":0,"total":7866}}
        ]}
        """
        try Data(json.utf8).write(to: chats.appendingPathComponent("session-2026-11-26T06-17-x.json"))

        let entries = GeminiReader().readEntries(
            antigravityConversationDirs: [],
            geminiCLITmpDir: tempDir.appendingPathComponent("tmp"),
            cutoff: Date(timeIntervalSince1970: 0)
        )
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.inputTokens, 7601 - 3104)
        XCTAssertEqual(entry.cacheReadTokens, 3104)
        XCTAssertEqual(entry.outputTokens, 27 + 238)
        XCTAssertEqual(entry.totalTokens, 7866)
    }

    // MARK: - Quota

    func testQuotaGroupsModelsIntoSharedBuckets() throws {
        let json = """
        {"userStatus":{"cascadeModelConfigData":{"clientModelConfigs":[
          {"label":"Gemini 4 Neon (High)","quotaInfo":{"remainingFraction":0.25,"resetTime":"2026-11-26T13:16:26Z"}},
          {"label":"Orchestrator (Neon)","quotaInfo":{"remainingFraction":0.25,"resetTime":"2026-11-26T13:16:26Z"}},
          {"label":"Gemini 3.8 Flash (Low)","quotaInfo":{"remainingFraction":0.25,"resetTime":"2026-11-26T13:16:26Z"}},
          {"label":"Claude Opus 5.5 (Low)","quotaInfo":{"resetTime":"2026-11-28T07:20:09Z"}},
          {"label":"GPT-OSS 120B (Medium)","quotaInfo":{"resetTime":"2026-11-28T07:20:09Z"}},
          {"label":"No quota model"}
        ]}}}
        """
        let now = Date()
        let quota = try XCTUnwrap(AntigravityQuotaReader.parse(Data(json.utf8), now: now))
        XCTAssertEqual(quota.pools.map(\.name), ["Gemini", "Claude/GPT"])
        XCTAssertEqual(quota.pools[0].usedPct, 75, accuracy: 0.001)
        XCTAssertEqual(quota.pools[1].usedPct, 100, "omitted proto3 zero means exhausted")
        XCTAssertEqual(quota.pools[1].resetsAt, ISO8601DateFormatter().date(from: "2026-11-28T07:20:09Z"))
        XCTAssertEqual(quota.headlinePct, 75)
        XCTAssertNil(AntigravityQuotaReader.parse(Data("{}".utf8), now: now))
    }

    func testQuotaReaderIgnoresHubsOfExitedProcesses() throws {
        let daemon = tempDir.appendingPathComponent("daemon", isDirectory: true)
        try FileManager.default.createDirectory(at: daemon, withIntermediateDirectories: true)
        let hub = #"{"pid":2147483000,"httpPort":1,"httpsPort":2,"csrfToken":"t"}"#
        try Data(hub.utf8).write(to: daemon.appendingPathComponent("hub_1.json"))
        XCTAssertNil(AntigravityQuotaReader.read(daemonDirs: [daemon], now: Date()))
    }

    // MARK: - Store

    @MainActor
    func testStoreAddsGeminiUsageToTodayAndWeek() {
        let now = Date()
        let entry = UsageEntry(id: "g", timestamp: now, model: "gemini-4-neon", inputTokens: 100,
                               outputTokens: 20, cacheCreationTokens: 0, cacheCreation1hTokens: 0,
                               cacheReadTokens: 1000, speed: nil, inferenceGeo: nil, costUSD: nil)
        let quota = AntigravityQuota(pools: [QuotaPool(name: "Gemini", usedPct: 40, resetsAt: nil)],
                                     updatedAt: now)
        let store = UsageStore(
            projectsDir: tempDir, autoload: false, autoRefresh: false, now: { now },
            claudeRateSnapshotReader: { (nil, .waitingForSessionData) },
            codexRateReader: { nil }, codexEntriesReader: { _ in [] },
            geminiEntriesReader: { _ in [entry] }, antigravityQuotaReader: { quota },
            pricingLoader: { _ in }
        )
        store.refreshSynchronouslyForTesting()

        XCTAssertEqual(store.gmEntries.count, 1)
        XCTAssertEqual(store.usageSummary.today.tokens, 1120)
        XCTAssertEqual(store.usageSummary.today.models.first?.source, .gemini)
        XCTAssertTrue(store.usageSummary.today.hasUnknownCost)
        XCTAssertEqual(store.usageSummary.weekly.last?.tokens, 1120)
        XCTAssertEqual(store.antigravityQuota, quota)
    }

    // MARK: - Fixtures

    private func generation(model: String, display: String, input: UInt64, output: UInt64,
                            cacheRead: UInt64, responseID: String,
                            producedSteps: [UInt64], lastStep: Int) -> Data {
        var usage = PB().varint(1, 1532).varint(2, input).varint(3, output).varint(5, cacheRead)
        if !responseID.isEmpty { usage = usage.string(11, responseID) }
        var chat = PB().varint(3, 1532).bytes(4, usage.data).string(19, model)
        chat = chat.bytes(20, PB().string(1, "last_step_index").string(2, String(lastStep)).data)
        if !display.isEmpty { chat = chat.string(21, display) }
        var top = PB()
        if !producedSteps.isEmpty { top = top.packed(2, producedSteps) }
        return top.string(4, "exec").bytes(1, chat.data).data
    }

    private func makeDatabase(at url: URL, steps: [(Int, Date)], generations: [(Int, Data)]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let db = try open(url)
        // Antigravity databases use WAL mode; once a conversation is closed
        // only the main file remains, which the system SQLite cannot open
        // read-only without immutable mode.
        try exec(db, "PRAGMA journal_mode=WAL")
        try exec(db, "CREATE TABLE steps (idx integer PRIMARY KEY, metadata blob)")
        try exec(db, "CREATE TABLE gen_metadata (idx integer PRIMARY KEY, data blob, size integer NOT NULL DEFAULT 0)")
        for (index, date) in steps {
            let seconds = UInt64(date.timeIntervalSince1970)
            let nanos = UInt64((date.timeIntervalSince1970 - Double(seconds)) * 1_000_000_000)
            let metadata = PB().bytes(1, PB().varint(1, seconds).varint(2, nanos).data).varint(11, 1532).data
            try insert(db, "INSERT INTO steps (idx, metadata) VALUES (?, ?)", index, metadata)
        }
        for (index, data) in generations {
            try insert(db, "INSERT INTO gen_metadata (idx, data) VALUES (?, ?)", index, data)
        }
        sqlite3_close(db)
        removeSideFiles(of: url)
    }

    /// Apple's SQLite keeps -wal/-shm after a checkpointing close;
    /// Antigravity's own SQLite removes them. Reproduce the latter.
    private func removeSideFiles(of url: URL) {
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    private func insertGeneration(into url: URL, index: Int, data: Data) throws {
        let db = try open(url)
        try insert(db, "INSERT INTO gen_metadata (idx, data) VALUES (?, ?)", index, data)
        sqlite3_close(db)
        removeSideFiles(of: url)
    }

    private func open(_ url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw FixtureError.sqlite }
        return db
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw FixtureError.sqlite }
    }

    private func insert(_ db: OpaquePointer, _ sql: String, _ index: Int, _ blob: Data) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FixtureError.sqlite
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(index))
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(blob.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw FixtureError.sqlite }
    }

    private enum FixtureError: Error { case sqlite }
}

/// Tiny protobuf writer for fixtures.
private struct PB {
    var data = Data()

    @discardableResult
    func varint(_ field: Int, _ value: UInt64) -> PB {
        var copy = self
        copy.appendVarint(UInt64(field << 3))
        copy.appendVarint(value)
        return copy
    }

    func bytes(_ field: Int, _ payload: Data) -> PB {
        var copy = self
        copy.appendVarint(UInt64(field << 3 | 2))
        copy.appendVarint(UInt64(payload.count))
        copy.data.append(payload)
        return copy
    }

    func string(_ field: Int, _ value: String) -> PB { bytes(field, Data(value.utf8)) }

    func packed(_ field: Int, _ values: [UInt64]) -> PB {
        var inner = PB()
        for value in values { inner.appendVarint(value) }
        return bytes(field, inner.data)
    }

    func fixed64(_ field: Int, _ value: UInt64) -> PB {
        var copy = self
        copy.appendVarint(UInt64(field << 3 | 1))
        for shift in 0..<8 { copy.data.append(UInt8(truncatingIfNeeded: value >> (8 * UInt64(shift)))) }
        return copy
    }

    private mutating func appendVarint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7f) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }
}

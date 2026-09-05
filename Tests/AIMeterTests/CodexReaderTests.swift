import Foundation
import XCTest
@testable import AIMeter

final class CodexReaderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if tempDir != nil {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    func testReadEntriesUsesLastTokenUsageAsDelta() throws {
        let sessionsDir = try makeSessionsDir()
        let file = sessionsDir.appendingPathComponent("2026/04/14/rollout-a.jsonl")
        let start = Date(timeIntervalSince1970: 1_776_150_000)

        try write([
            try jsonLine([
                "timestamp": iso(start),
                "type": "session_meta",
                "payload": ["id": "session-a"],
            ]),
            try jsonLine([
                "timestamp": iso(start),
                "type": "turn_context",
                "payload": ["model": "gpt-5.4-mini"],
            ]),
            try tokenCountLine(
                timestamp: start.addingTimeInterval(1),
                last: ["input_tokens": 100, "cached_input_tokens": 40, "output_tokens": 5, "reasoning_output_tokens": 0, "total_tokens": 105],
                total: ["input_tokens": 100, "cached_input_tokens": 40, "output_tokens": 5, "reasoning_output_tokens": 0, "total_tokens": 105]
            ),
            try tokenCountLine(
                timestamp: start.addingTimeInterval(2),
                last: ["input_tokens": 30, "cached_input_tokens": 10, "output_tokens": 2, "reasoning_output_tokens": 1, "total_tokens": 32],
                total: ["input_tokens": 130, "cached_input_tokens": 50, "output_tokens": 7, "reasoning_output_tokens": 1, "total_tokens": 137]
            ),
        ].joined(separator: "\n") + "\n", to: file)

        let entries = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessionsDir))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.model), ["gpt-5.4-mini", "gpt-5.4-mini"])
        XCTAssertEqual(entries.map(\.totalTokens), [105, 32])
        XCTAssertEqual(entries.map(\.cachedInputTokens), [40, 10])
    }

    func testReadEntriesIgnoresRepeatedLastTokenUsageWhenTotalsDoNotAdvance() throws {
        let sessionsDir = try makeSessionsDir()
        let file = sessionsDir.appendingPathComponent("2026/04/14/rollout-repeat.jsonl")
        let start = Date(timeIntervalSince1970: 1_776_150_050)
        let usage = [
            "input_tokens": 100,
            "cached_input_tokens": 40,
            "output_tokens": 5,
            "reasoning_output_tokens": 0,
            "total_tokens": 105,
        ]

        try write([
            try jsonLine([
                "timestamp": iso(start),
                "type": "session_meta",
                "payload": ["id": "session-repeat"],
            ]),
            try jsonLine([
                "timestamp": iso(start),
                "type": "turn_context",
                "payload": ["model": "gpt-5.4-mini"],
            ]),
            try tokenCountLine(timestamp: start.addingTimeInterval(1), last: usage, total: usage),
            try tokenCountLine(timestamp: start.addingTimeInterval(2), last: usage, total: usage),
        ].joined(separator: "\n") + "\n", to: file)

        let entries = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessionsDir))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].totalTokens, 105)
        XCTAssertEqual(entries[0].inputTokens, 100)
        XCTAssertEqual(entries[0].cachedInputTokens, 40)
    }

    func testReadEntriesFallsBackToTotalUsageDiff() throws {
        let sessionsDir = try makeSessionsDir()
        let file = sessionsDir.appendingPathComponent("2026/04/14/rollout-b.jsonl")
        let start = Date(timeIntervalSince1970: 1_776_150_100)

        try write([
            try jsonLine([
                "timestamp": iso(start),
                "type": "session_meta",
                "payload": ["id": "session-b"],
            ]),
            try jsonLine([
                "timestamp": iso(start),
                "type": "turn_context",
                "payload": ["model": "gpt-5.4"],
            ]),
            try tokenCountLine(
                timestamp: start.addingTimeInterval(1),
                total: ["input_tokens": 100, "cached_input_tokens": 20, "output_tokens": 10, "reasoning_output_tokens": 0, "total_tokens": 110]
            ),
            try tokenCountLine(
                timestamp: start.addingTimeInterval(2),
                total: ["input_tokens": 180, "cached_input_tokens": 60, "output_tokens": 15, "reasoning_output_tokens": 0, "total_tokens": 195]
            ),
        ].joined(separator: "\n") + "\n", to: file)

        let entries = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessionsDir))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.totalTokens), [110, 85])
        XCTAssertEqual(entries.map(\.inputTokens), [100, 80])
        XCTAssertEqual(entries.map(\.cachedInputTokens), [20, 40])
        XCTAssertEqual(entries.map(\.outputTokens), [10, 5])
    }

    func testReadEntriesUsesPreCutoffTotalForFirstVisibleDelta() throws {
        let sessionsDir = try makeSessionsDir()
        let file = sessionsDir.appendingPathComponent("2026/04/14/rollout-c.jsonl")
        let start = Date(timeIntervalSince1970: 1_776_150_200)
        let cutoff = start.addingTimeInterval(2)

        try write([
            try jsonLine([
                "timestamp": iso(start),
                "type": "session_meta",
                "payload": ["id": "session-c"],
            ]),
            try jsonLine([
                "timestamp": iso(start),
                "type": "turn_context",
                "payload": ["model": "gpt-5.4"],
            ]),
            try tokenCountLine(
                timestamp: start.addingTimeInterval(1),
                total: ["input_tokens": 100, "cached_input_tokens": 20, "output_tokens": 10, "reasoning_output_tokens": 0, "total_tokens": 110]
            ),
            try tokenCountLine(
                timestamp: start.addingTimeInterval(3),
                total: ["input_tokens": 180, "cached_input_tokens": 60, "output_tokens": 15, "reasoning_output_tokens": 0, "total_tokens": 195]
            ),
        ].joined(separator: "\n") + "\n", to: file)

        let entries = try XCTUnwrap(CodexReader.readEntries(since: cutoff, sessionsDir: sessionsDir))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].totalTokens, 85)
        XCTAssertEqual(entries[0].inputTokens, 80)
        XCTAssertEqual(entries[0].cachedInputTokens, 40)
        XCTAssertEqual(entries[0].outputTokens, 5)
    }

    func testReadEntriesKeepsParserStateAcrossAppends() throws {
        let sessionsDir = try makeSessionsDir()
        let file = sessionsDir.appendingPathComponent("2026/04/14/rollout-d.jsonl")
        let start = Date(timeIntervalSince1970: 1_776_150_300)

        try write([
            try jsonLine([
                "timestamp": iso(start),
                "type": "session_meta",
                "payload": ["id": "session-d"],
            ]),
            try jsonLine([
                "timestamp": iso(start),
                "type": "turn_context",
                "payload": ["model": "gpt-5.4"],
            ]),
            try tokenCountLine(
                timestamp: start.addingTimeInterval(1),
                total: ["input_tokens": 100, "cached_input_tokens": 20, "output_tokens": 10, "reasoning_output_tokens": 0, "total_tokens": 110]
            ),
        ].joined(separator: "\n") + "\n", to: file)

        _ = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessionsDir))

        try append(
            try tokenCountLine(
                timestamp: start.addingTimeInterval(2),
                total: ["input_tokens": 180, "cached_input_tokens": 60, "output_tokens": 15, "reasoning_output_tokens": 0, "total_tokens": 195]
            ) + "\n",
            to: file
        )

        let entries = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessionsDir))
        XCTAssertEqual(entries.map(\.totalTokens), [110, 85])
        XCTAssertEqual(entries.map(\.inputTokens), [100, 80])
    }

    func testReadEntriesParsesCompleteFinalLineWithoutTrailingNewline() throws {
        let sessionsDir = try makeSessionsDir()
        let file = sessionsDir.appendingPathComponent("2026/04/14/rollout-e.jsonl")
        let start = Date(timeIntervalSince1970: 1_776_150_400)

        try write([
            try jsonLine([
                "timestamp": iso(start),
                "type": "session_meta",
                "payload": ["id": "session-e"],
            ]),
            try jsonLine([
                "timestamp": iso(start),
                "type": "turn_context",
                "payload": ["model": "gpt-5.4"],
            ]),
            try tokenCountLine(
                timestamp: start.addingTimeInterval(1),
                total: ["input_tokens": 100, "cached_input_tokens": 20, "output_tokens": 10, "reasoning_output_tokens": 0, "total_tokens": 110]
            ),
        ].joined(separator: "\n"), to: file)

        let entries = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessionsDir))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].totalTokens, 110)
        XCTAssertEqual(entries[0].sessionID, "session-e")
    }

    private func makeSessionsDir() throws -> URL {
        let dir = tempDir.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testCacheWritesAndServiceTierSurviveIncrementalParsing() throws {
        let sessions = try makeSessionsDir()
        let file = sessions.appendingPathComponent("rollout-cache.jsonl")
        let start = Date(timeIntervalSince1970: 1_788_600_000)
        let usage = ["input_tokens": 100, "cached_input_tokens": 40, "cache_write_input_tokens": 60,
                     "output_tokens": 10, "reasoning_output_tokens": 5, "total_tokens": 110]
        let settings: [String: Any] = ["type": "event_msg", "payload": [
            "type": "thread_settings_applied", "thread_id": "session-cache",
            "thread_settings": ["model": "gpt-6-astra", "service_tier": "priority"]]]
        try write([
            try jsonLine(["type": "session_meta", "payload": ["id": "session-cache"]]),
            try jsonLine(settings),
            try jsonLine(["type": "turn_context", "payload": ["model": "gpt-6-astra"]]),
            try tokenCountLine(timestamp: start, last: usage, total: usage)
        ].joined(separator: "\n") + "\n", to: file)
        var entries = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessions))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].cacheWriteInputTokens, 60)
        XCTAssertEqual(entries[0].serviceTier, "priority")
        XCTAssertEqual(entries[0].cost, 2 * (40e-6 + 60 * 12.5e-6 + 10 * 50e-6), accuracy: 1e-12)
        // Cumulative-only fallback must retain the cache-write delta too.
        try append(try tokenCountLine(timestamp: start.addingTimeInterval(1), total: usage.mapValues { $0 * 2 }) + "\n", to: file)
        entries = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessions))
        XCTAssertEqual(entries.map(\.cacheWriteInputTokens), [60, 60])
        XCTAssertEqual(entries[0].cost, entries[1].cost, accuracy: 1e-12)
        // Switching models must not inherit the previous model's tier.
        try append(try jsonLine(["type": "turn_context", "payload": ["model": "gpt-5.4-mini"]]) + "\n"
                   + tokenCountLine(timestamp: start.addingTimeInterval(2), last: usage, total: usage.mapValues { $0 * 3 }) + "\n", to: file)
        entries = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessions))
        XCTAssertNil(entries.last?.serviceTier)
        XCTAssertTrue(entries.last?.hasKnownCost == true)
    }

    func testCounterRestartDoesNotDropFirstNewRequestOrDuplicateRepeat() throws {
        let sessions = try makeSessionsDir()
        let file = sessions.appendingPathComponent("rollout-reset.jsonl")
        let start = Date(timeIntervalSince1970: 1_788_600_000)
        let big = ["input_tokens": 1000, "output_tokens": 100, "total_tokens": 1100]
        let small = ["input_tokens": 100, "output_tokens": 10, "total_tokens": 110]
        try write([
            try jsonLine(["type": "turn_context", "payload": ["model": "gpt-6-astra"]]),
            try tokenCountLine(timestamp: start, last: big, total: big),
            try tokenCountLine(timestamp: start.addingTimeInterval(1), last: small, total: small),
            try tokenCountLine(timestamp: start.addingTimeInterval(2), last: small, total: small)
        ].joined(separator: "\n") + "\n", to: file)
        let entries = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessions))
        XCTAssertEqual(entries.map(\.totalTokens), [1100, 110])
    }

    func testUnknownServiceTierMarksCostIncomplete() throws {
        let sessions = try makeSessionsDir()
        let file = sessions.appendingPathComponent("rollout-tier.jsonl")
        let start = Date(timeIntervalSince1970: 1_788_600_000)
        try write(try jsonLine(["type": "turn_context", "payload": ["model": "gpt-6-astra", "service_tier": "custom"]])
                  + "\n" + tokenCountLine(timestamp: start, total: ["input_tokens": 100, "total_tokens": 100]) + "\n", to: file)
        let entry = try XCTUnwrap(CodexReader.readEntries(since: start, sessionsDir: sessions)?.first)
        XCTAssertFalse(entry.hasKnownCost)
        XCTAssertEqual(entry.cost, 0)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = text.data(using: .utf8) else {
            XCTFail("failed to encode UTF-8 text")
            return
        }
        try data.write(to: url)
    }

    private func append(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            XCTFail("failed to encode UTF-8 text")
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            XCTFail("expected file at \(url.path)")
            return
        }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        try handle.write(contentsOf: data)
    }

    private func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            XCTFail("failed to decode JSON line")
            return ""
        }
        return text
    }

    private func tokenCountLine(
        timestamp: Date,
        last: [String: Int]? = nil,
        total: [String: Int]
    ) throws -> String {
        var info: [String: Any] = ["total_token_usage": total]
        if let last {
            info["last_token_usage"] = last
        }
        return try jsonLine([
            "timestamp": iso(timestamp),
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": info,
            ],
        ])
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

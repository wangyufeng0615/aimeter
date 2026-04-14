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

    private func makeSessionsDir() throws -> URL {
        let dir = tempDir.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = text.data(using: .utf8) else {
            XCTFail("failed to encode UTF-8 text")
            return
        }
        try data.write(to: url)
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

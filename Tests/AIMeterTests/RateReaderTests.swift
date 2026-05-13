import Foundation
import XCTest
@testable import AIMeter

final class RateReaderTests: XCTestCase {
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

    func testClaudeInspectReadsRateLimitsAndWritesCache() throws {
        let now = Date(timeIntervalSince1970: 1_776_170_000)
        let usageFile = tempDir.appendingPathComponent("usage-rate.json")
        let cacheFile = tempDir.appendingPathComponent("cache/claude-rate-v1.json")

        try writeJSON(
            [
                "rate_limits": [
                    "five_hour": [
                        "used_percentage": 12.0,
                        "resets_at": 1_776_186_000.0,
                    ],
                    "seven_day": [
                        "used_percentage": 34.0,
                    ],
                ],
            ],
            to: usageFile,
            modDate: now
        )

        let result = ClaudeRateReader.inspect(filePath: usageFile, cachePath: cacheFile, now: now)
        XCTAssertEqual(result.status, .available)
        XCTAssertEqual(result.rate?.fiveHourPct, 12.0)
        XCTAssertEqual(result.rate?.sevenDayPct, 34.0)
        XCTAssertEqual(result.rate?.fiveHourResetsAt, normalizeTimestamp(1_776_186_000.0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
    }

    func testClaudeInspectFallsBackToCachedRateWhenLatestSnapshotHasNoRateLimits() throws {
        let now = Date(timeIntervalSince1970: 1_776_170_000)
        let usageFile = tempDir.appendingPathComponent("usage-rate.json")
        let cacheFile = tempDir.appendingPathComponent("cache/claude-rate-v1.json")

        try writeJSON(
            [
                "rate_limits": [
                    "five_hour": ["used_percentage": 18.0],
                    "seven_day": ["used_percentage": 52.0],
                ],
            ],
            to: usageFile,
            modDate: now
        )
        _ = ClaudeRateReader.inspect(filePath: usageFile, cachePath: cacheFile, now: now)

        try writeJSON(
            [
                "session_id": "abc",
                "cost": ["total_cost_usd": 0.0],
                "context_window": ["used_percentage": NSNull()],
            ],
            to: usageFile,
            modDate: now.addingTimeInterval(60)
        )

        let result = ClaudeRateReader.inspect(
            filePath: usageFile,
            cachePath: cacheFile,
            now: now.addingTimeInterval(60)
        )
        XCTAssertEqual(result.status, .available)
        XCTAssertEqual(result.rate?.fiveHourPct, 18.0)
        XCTAssertEqual(result.rate?.sevenDayPct, 52.0)
    }

    func testClaudeInspectReturnsUnavailableWithoutRateLimitsOrCache() throws {
        let now = Date(timeIntervalSince1970: 1_776_170_000)
        let usageFile = tempDir.appendingPathComponent("usage-rate.json")
        let cacheFile = tempDir.appendingPathComponent("cache/claude-rate-v1.json")

        try writeJSON(
            [
                "session_id": "abc",
                "cost": ["total_cost_usd": 0.0],
                "context_window": ["used_percentage": NSNull()],
            ],
            to: usageFile,
            modDate: now
        )

        let result = ClaudeRateReader.inspect(filePath: usageFile, cachePath: cacheFile, now: now)
        XCTAssertNil(result.rate)
        XCTAssertEqual(result.status, .rateLimitsUnavailable)
    }

    func testCodexReadAcceptsTopLevelRateLimits() throws {
        let now = Date(timeIntervalSince1970: 1_776_180_000)
        let sessionsDir = tempDir.appendingPathComponent("codex-a/sessions", isDirectory: true)
        let rollout = sessionsDir.appendingPathComponent("2026/05/13/rollout-a.jsonl")
        try write(
            codexRateLine(fiveHour: 42, sevenDay: 55, resetsAt: 1_776_183_600),
            to: rollout,
            modDate: now
        )

        let rate = CodexRateReader.read(sessionsDir: sessionsDir, now: now)

        XCTAssertEqual(rate?.fiveHourPct, 42)
        XCTAssertEqual(rate?.sevenDayPct, 55)
        XCTAssertEqual(rate?.fiveHourResetsAt, normalizeTimestamp(1_776_183_600))
    }

    func testCodexLatestRolloutCacheIsScopedToSessionsDir() throws {
        let now = Date(timeIntervalSince1970: 1_776_180_100)
        let firstDir = tempDir.appendingPathComponent("codex-first/sessions", isDirectory: true)
        let secondDir = tempDir.appendingPathComponent("codex-second/sessions", isDirectory: true)
        try write(
            codexRateLine(fiveHour: 11, sevenDay: 22, resetsAt: 1_776_183_700),
            to: firstDir.appendingPathComponent("2026/05/13/rollout-first.jsonl"),
            modDate: now
        )
        try write(
            codexRateLine(fiveHour: 77, sevenDay: 88, resetsAt: 1_776_183_800),
            to: secondDir.appendingPathComponent("2026/05/13/rollout-second.jsonl"),
            modDate: now.addingTimeInterval(1)
        )

        let first = CodexRateReader.read(sessionsDir: firstDir, now: now)
        let second = CodexRateReader.read(sessionsDir: secondDir, now: now.addingTimeInterval(1))

        XCTAssertEqual(first?.fiveHourPct, 11)
        XCTAssertEqual(second?.fiveHourPct, 77)
        XCTAssertEqual(second?.sevenDayPct, 88)
    }

    private func writeJSON(_ object: [String: Any], to url: URL, modDate: Date) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: url.path)
    }

    private func write(_ text: String, to url: URL, modDate: Date) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.data(using: .utf8).unwrap().write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: url.path)
    }

    private func codexRateLine(fiveHour: Double, sevenDay: Double, resetsAt: Double) throws -> String {
        let object: [String: Any] = [
            "timestamp": "2026-05-13T00:00:00.000Z",
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": [:],
            ],
            "rate_limits": [
                "limit_id": "codex",
                "primary": [
                    "used_percent": fiveHour,
                    "window_minutes": 300,
                    "resets_at": resetsAt,
                ],
                "secondary": [
                    "used_percent": sevenDay,
                    "window_minutes": 10080,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8).unwrap() + "\n"
    }
}

private extension Optional {
    func unwrap(file: StaticString = #filePath, line: UInt = #line) -> Wrapped {
        guard let value = self else {
            XCTFail("unexpected nil", file: file, line: line)
            fatalError("unexpected nil")
        }
        return value
    }
}

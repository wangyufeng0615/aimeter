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

    private func writeJSON(_ object: [String: Any], to url: URL, modDate: Date) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: url.path)
    }
}

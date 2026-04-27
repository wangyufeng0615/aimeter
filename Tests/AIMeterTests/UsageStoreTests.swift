import Combine
import Foundation
import XCTest
@testable import AIMeter

final class UsageStoreTests: XCTestCase {
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

    @MainActor
    func testIncrementalRefreshReadsOnlyAppendedBytes() throws {
        let projectsDir = try makeProjectsDir()
        let logFile = projectsDir.appendingPathComponent("session.jsonl")
        let now = Date(timeIntervalSince1970: 1_776_150_000)

        try write([
            try usageLine(messageID: "m1", requestID: "r1", timestamp: now, input: 100),
            try usageLine(messageID: "m2", requestID: "r2", timestamp: now.addingTimeInterval(5), input: 200),
        ].joined(separator: "\n") + "\n", to: logFile)

        let store = makeStore(projectsDir: projectsDir, now: now)
        store.refreshSynchronouslyForTesting()

        let firstStats = store.lastTokenLoadStats
        XCTAssertEqual(store.ccEntries.count, 2)
        XCTAssertEqual(firstStats.fullParsedFiles, 1)
        XCTAssertEqual(firstStats.incrementalFiles, 0)
        XCTAssertEqual(firstStats.reusedFiles, 0)
        XCTAssertGreaterThan(firstStats.parsedBytes, 0)

        try append(try usageLine(messageID: "m3", requestID: "r3", timestamp: now.addingTimeInterval(10), input: 300) + "\n", to: logFile)
        store.refreshSynchronouslyForTesting()

        let secondStats = store.lastTokenLoadStats
        XCTAssertEqual(store.ccEntries.count, 3)
        XCTAssertEqual(store.ccEntries.map(\.id), ["m1:r1", "m2:r2", "m3:r3"])
        XCTAssertEqual(secondStats.fullParsedFiles, 0)
        XCTAssertEqual(secondStats.incrementalFiles, 1)
        XCTAssertEqual(secondStats.reusedFiles, 0)
        XCTAssertLessThan(secondStats.parsedBytes, firstStats.parsedBytes)
    }

    @MainActor
    func testIncrementalRefreshCompletesBufferedPartialLine() throws {
        let projectsDir = try makeProjectsDir()
        let logFile = projectsDir.appendingPathComponent("session.jsonl")
        let now = Date(timeIntervalSince1970: 1_776_150_100)

        let first = try usageLine(messageID: "m1", requestID: "r1", timestamp: now, input: 11)
        let second = try usageLine(messageID: "m2", requestID: "r2", timestamp: now.addingTimeInterval(3), input: 22)
        let splitIndex = second.index(second.startIndex, offsetBy: second.count / 2)

        try write(first + "\n" + String(second[..<splitIndex]), to: logFile)

        let store = makeStore(projectsDir: projectsDir, now: now)
        store.refreshSynchronouslyForTesting()

        XCTAssertEqual(store.ccEntries.map(\.id), ["m1:r1"])
        XCTAssertEqual(store.lastTokenLoadStats.fullParsedFiles, 1)

        try append(String(second[splitIndex...]) + "\n", to: logFile)
        store.refreshSynchronouslyForTesting()

        XCTAssertEqual(store.ccEntries.map(\.id), ["m1:r1", "m2:r2"])
        XCTAssertEqual(store.lastTokenLoadStats.incrementalFiles, 1)
    }

    @MainActor
    func testCachedClaudeEntriesArePrunedWhenTheyAgeOut() throws {
        let projectsDir = try makeProjectsDir()
        let logFile = projectsDir.appendingPathComponent("session.jsonl")
        let base = Date(timeIntervalSince1970: 1_776_150_150)
        var currentDate = base

        try write([
            try usageLine(messageID: "old", requestID: "r1", timestamp: base.addingTimeInterval(-6 * 86400), input: 10),
            try usageLine(messageID: "new", requestID: "r2", timestamp: base, input: 20),
        ].joined(separator: "\n") + "\n", to: logFile)
        try setModificationDate(base, for: logFile)

        let store = makeStore(projectsDir: projectsDir, nowProvider: { currentDate })
        store.refreshSynchronouslyForTesting()
        XCTAssertEqual(store.ccEntries.map(\.id), ["old:r1", "new:r2"])

        currentDate = base.addingTimeInterval(2 * 86400)
        store.refreshSynchronouslyForTesting()

        XCTAssertEqual(store.ccEntries.map(\.id), ["new:r2"])
        XCTAssertEqual(store.lastTokenLoadStats.reusedFiles, 1)
    }

    @MainActor
    func testUnchangedRefreshDoesNotRepublishObjectWillChange() throws {
        let projectsDir = try makeProjectsDir()
        let logFile = projectsDir.appendingPathComponent("session.jsonl")
        let now = Date(timeIntervalSince1970: 1_776_150_200)

        try write(try usageLine(messageID: "m1", requestID: "r1", timestamp: now, model: "claude-opus-4-6", input: 42) + "\n", to: logFile)

        let codexEntries = [
            CodexReader.UsageEntry(
                id: "session-1:1",
                sessionID: "session-1",
                timestamp: now,
                model: "gpt-5.4",
                inputTokens: 1200,
                cachedInputTokens: 200,
                outputTokens: 34,
                reasoningOutputTokens: 0,
                totalTokens: 1234
            ),
        ]
        let rate = RateLimit(
            fiveHourPct: 12,
            sevenDayPct: 34,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            updatedAt: now
        )

        let store = makeStore(
            projectsDir: projectsDir,
            now: now,
            claudeRate: rate,
            codexRate: rate,
            codexEntries: codexEntries
        )

        var changeCount = 0
        let cancellable = store.objectWillChange.sink {
            changeCount += 1
        }
        defer { cancellable.cancel() }

        store.refreshSynchronouslyForTesting()
        XCTAssertGreaterThan(changeCount, 0)

        changeCount = 0
        store.refreshSynchronouslyForTesting()
        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(store.lastTokenLoadStats.reusedFiles, 1)
    }

    @MainActor
    func testRefreshReadsClaudeRateSnapshotOnce() throws {
        let projectsDir = try makeProjectsDir()
        let now = Date(timeIntervalSince1970: 1_776_150_250)
        let rate = RateLimit(
            fiveHourPct: 12,
            sevenDayPct: 34,
            fiveHourResetsAt: now.addingTimeInterval(3600),
            updatedAt: now
        )
        var calls = 0

        let store = UsageStore(
            projectsDir: projectsDir,
            autoload: false,
            autoRefresh: false,
            now: { now },
            claudeRateSnapshotReader: {
                calls += 1
                return (rate, .available)
            },
            codexRateReader: { nil },
            codexEntriesReader: { _ in [] },
            pricingLoader: {}
        )

        store.refreshSynchronouslyForTesting()

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.claudeRate, rate)
        XCTAssertEqual(store.claudeRateStatus, .available)
    }

    @MainActor
    func testRewrittenFileFallsBackToFullParse() throws {
        let projectsDir = try makeProjectsDir()
        let logFile = projectsDir.appendingPathComponent("session.jsonl")
        let now = Date(timeIntervalSince1970: 1_776_150_300)

        try write([
            try usageLine(messageID: "m1", requestID: "r1", timestamp: now, input: 10),
            try usageLine(messageID: "m2", requestID: "r2", timestamp: now.addingTimeInterval(2), input: 20),
        ].joined(separator: "\n") + "\n", to: logFile)

        let store = makeStore(projectsDir: projectsDir, now: now)
        store.refreshSynchronouslyForTesting()
        XCTAssertEqual(store.ccEntries.map(\.id), ["m1:r1", "m2:r2"])

        try write(try usageLine(messageID: "m3", requestID: "r3", timestamp: now.addingTimeInterval(4), input: 30) + "\n", to: logFile)
        store.refreshSynchronouslyForTesting()

        XCTAssertEqual(store.ccEntries.map(\.id), ["m3:r3"])
        XCTAssertEqual(store.lastTokenLoadStats.fullParsedFiles, 1)
        XCTAssertEqual(store.lastTokenLoadStats.incrementalFiles, 0)
    }

    @MainActor
    func testClaudeModelsExcludeSyntheticEntries() throws {
        let projectsDir = try makeProjectsDir()
        let logFile = projectsDir.appendingPathComponent("session.jsonl")
        let now = Date(timeIntervalSince1970: 1_776_150_400)

        try write([
            try usageLine(messageID: "m1", requestID: "r1", timestamp: now, model: "<synthetic>", input: 0, output: 0),
            try usageLine(messageID: "m2", requestID: "r2", timestamp: now.addingTimeInterval(1), model: "claude-opus-4-6", input: 100, output: 20),
        ].joined(separator: "\n") + "\n", to: logFile)

        let store = makeStore(projectsDir: projectsDir, now: now)
        store.refreshSynchronouslyForTesting()

        XCTAssertEqual(store.ccEntries.map(\.model), ["<synthetic>", "claude-opus-4-6"])
        XCTAssertEqual(store.ccModels.map(\.model), ["claude-opus-4-6"])
    }

    private func makeStore(
        projectsDir: URL,
        now: Date,
        claudeRate: RateLimit? = nil,
        codexRate: RateLimit? = nil,
        codexEntries: [CodexReader.UsageEntry]? = []
    ) -> UsageStore {
        makeStore(
            projectsDir: projectsDir,
            nowProvider: { now },
            claudeRate: claudeRate,
            codexRate: codexRate,
            codexEntries: codexEntries
        )
    }

    private func makeStore(
        projectsDir: URL,
        nowProvider: @escaping UsageStore.Clock,
        claudeRate: RateLimit? = nil,
        codexRate: RateLimit? = nil,
        codexEntries: [CodexReader.UsageEntry]? = []
    ) -> UsageStore {
        UsageStore(
            projectsDir: projectsDir,
            autoload: false,
            autoRefresh: false,
            now: nowProvider,
            claudeRateReader: { claudeRate },
            claudeRateStatusReader: { claudeRate == nil ? .waitingForSessionData : .available },
            codexRateReader: { codexRate },
            codexEntriesReader: { _ in codexEntries },
            pricingLoader: {}
        )
    }

    private func makeProjectsDir() throws -> URL {
        let dir = tempDir.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.data(using: .utf8).unwrap().write(to: url)
    }

    private func append(_ text: String, to url: URL) throws {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            XCTFail("expected file at \(url.path)")
            return
        }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        try handle.write(contentsOf: text.data(using: .utf8).unwrap())
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func usageLine(
        messageID: String,
        requestID: String,
        timestamp: Date,
        model: String = "claude-opus-4-6",
        input: Int,
        output: Int = 5,
        cacheCreation: Int = 0,
        cacheRead: Int = 0,
        costUSD: Double? = nil
    ) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var json: [String: Any] = [
            "type": "assistant",
            "timestamp": formatter.string(from: timestamp),
            "requestId": requestID,
            "message": [
                "id": messageID,
                "model": model,
                "usage": [
                    "input_tokens": input,
                    "output_tokens": output,
                    "cache_creation_input_tokens": cacheCreation,
                    "cache_read_input_tokens": cacheRead,
                ],
            ],
        ]
        if let costUSD {
            json["costUSD"] = costUSD
        }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return String(data: data, encoding: .utf8).unwrap()
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

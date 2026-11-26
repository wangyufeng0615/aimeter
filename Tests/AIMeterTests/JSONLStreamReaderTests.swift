import Foundation
import XCTest
@testable import AIMeter

final class JSONLStreamReaderTests: XCTestCase {
    func testOversizedPartialRecordStaysDiscardedAcrossAppends() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        let firstSize = JSONLStreamReader.maxLineBytes + 100
        try handle.truncate(atOffset: UInt64(firstSize))
        var values: [Int] = []
        let first = try XCTUnwrap(JSONLStreamReader.read(file, throughOffset: firstSize) {
            values.append($0["value"] as! Int)
        })
        XCTAssertTrue(first.discardingLine)
        XCTAssertTrue(first.trailingData.isEmpty)
        try handle.seekToEnd()
        // Even a valid JSON suffix belongs to the rejected record until newline.
        let suffix = Data("{\"value\":999}\n{\"value\":7}".utf8)
        try handle.write(contentsOf: suffix)
        let second = try XCTUnwrap(JSONLStreamReader.read(
            file, fromOffset: firstSize, throughOffset: firstSize + suffix.count,
            carryover: first.trailingData, discardingLine: first.discardingLine
        ) { values.append($0["value"] as! Int) })
        XCTAssertEqual(values, [7])
        XCTAssertFalse(second.discardingLine)
        XCTAssertTrue(second.trailingData.isEmpty)
    }

    func testRequiredMarkerSkipsRecordsWithoutItButKeepsFinalUnterminatedRecord() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let text = "{\"value\":1}\n{\"value\":2,\"input_tokens\":5}\n{\"value\":3,\"input_tokens\":1}"
        try Data(text.utf8).write(to: file)
        var values: [Int] = []
        let result = try XCTUnwrap(JSONLStreamReader.read(
            file, throughOffset: text.utf8.count, requiredMarker: Data("\"input_tokens\"".utf8)
        ) { values.append($0["value"] as! Int) })
        XCTAssertEqual(values, [2, 3])
        XCTAssertTrue(result.trailingData.isEmpty)

        // A tail cut before its marker is incomplete, not irrelevant.
        let partial = "{\"value\":4,"
        try Data(partial.utf8).write(to: file)
        let cut = try XCTUnwrap(JSONLStreamReader.read(
            file, throughOffset: partial.utf8.count, requiredMarker: Data("\"input_tokens\"".utf8)
        ) { values.append($0["value"] as! Int) })
        XCTAssertEqual(cut.trailingData, Data(partial.utf8))
    }
}

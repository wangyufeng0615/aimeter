import XCTest
@testable import AIMeter

final class FormattingTests: XCTestCase {
    func testTokenFormattingBelowOneMillionKeepsExistingUnits() {
        XCTAssertEqual(fmtTokens(0), "0")
        XCTAssertEqual(fmtTokens(999), "999")
        XCTAssertEqual(fmtTokens(1_000), "1K")
        XCTAssertEqual(fmtTokens(999_000), "999K")
        XCTAssertEqual(fmtTokens(999_499), "999K")
    }

    func testTokenFormattingPromotesRoundedThousandsToMillions() {
        XCTAssertEqual(fmtTokens(999_500), "1.0M")
        XCTAssertEqual(fmtTokens(999_999), "1.0M")
    }

    func testTokenFormattingUsesMillionsBelowBillionRoundingBoundary() {
        XCTAssertEqual(fmtTokens(1_000_000), "1.0M")
        XCTAssertEqual(fmtTokens(12_345_678), "12.3M")
        XCTAssertEqual(fmtTokens(999_000_000), "999.0M")
        XCTAssertEqual(fmtTokens(999_949_999), "999.9M")
    }

    func testTokenFormattingPromotesRoundedMillionsToBillions() {
        XCTAssertEqual(fmtTokens(999_950_000), "1.0B")
        XCTAssertEqual(fmtTokens(999_999_999), "1.0B")
        XCTAssertEqual(fmtTokens(1_000_000_000), "1.0B")
        XCTAssertEqual(fmtTokens(1_250_000_000), "1.2B")
        XCTAssertEqual(fmtTokens(12_345_678_900), "12.3B")
    }
}

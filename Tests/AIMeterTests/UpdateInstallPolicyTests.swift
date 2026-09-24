import XCTest
@testable import AIMeter

final class UpdateInstallPolicyTests: XCTestCase {
    func testReadyUpdateWaitsForQuietPeriod() {
        let readyAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(UpdateInstallPolicy.shouldInstall(
            readyAt: readyAt, now: readyAt.addingTimeInterval(29),
            hasVisibleInteractiveWindow: false
        ))
        XCTAssertTrue(UpdateInstallPolicy.shouldInstall(
            readyAt: readyAt, now: readyAt.addingTimeInterval(30),
            hasVisibleInteractiveWindow: false
        ))
    }

    func testReadyUpdateWaitsWhileMenuOrSettingsIsVisible() {
        let readyAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(UpdateInstallPolicy.shouldInstall(
            readyAt: readyAt, now: readyAt.addingTimeInterval(60),
            hasVisibleInteractiveWindow: true
        ))
        XCTAssertTrue(UpdateInstallPolicy.shouldInstall(
            readyAt: readyAt, now: readyAt.addingTimeInterval(75),
            hasVisibleInteractiveWindow: false
        ))
    }
}

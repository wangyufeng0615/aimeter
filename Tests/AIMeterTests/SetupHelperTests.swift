import Foundation
import XCTest
@testable import AIMeter

final class SetupHelperTests: XCTestCase {
    private var tempDir: URL!
    private var settingsFile: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        settingsFile = tempDir.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        if tempDir != nil {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        settingsFile = nil
    }

    // MARK: - isHookInstalled

    func testIsHookInstalledReturnsFalseWhenFileMissing() {
        XCTAssertFalse(SetupHelper.isHookInstalled(at: settingsFile))
    }

    func testIsHookInstalledReturnsFalseWithoutStatusLine() throws {
        try writeJSON(["other": "value"])
        XCTAssertFalse(SetupHelper.isHookInstalled(at: settingsFile))
    }

    func testIsHookInstalledReturnsFalseWhenCommandLacksTee() throws {
        try writeJSON([
            "statusLine": ["type": "command", "command": "echo hello"]
        ])
        XCTAssertFalse(SetupHelper.isHookInstalled(at: settingsFile))
    }

    func testIsHookInstalledMatchesTildeForm() throws {
        try writeJSON([
            "statusLine": ["type": "command", "command": "tee ~/.claude/usage-rate.json | echo"]
        ])
        XCTAssertTrue(SetupHelper.isHookInstalled(at: settingsFile))
    }

    func testIsHookInstalledMatchesExpandedHomePath() throws {
        // Some users save settings.json after `~` is shell-expanded
        try writeJSON([
            "statusLine": ["type": "command", "command": "tee /Users/test/.claude/usage-rate.json | echo"]
        ])
        XCTAssertTrue(SetupHelper.isHookInstalled(at: settingsFile))
    }

    // MARK: - preflight

    func testPreflightReturnsNilWhenFileMissing() {
        XCTAssertNil(SetupHelper.preflight(at: settingsFile))
    }

    func testPreflightDetectsSymlink() throws {
        let realFile = tempDir.appendingPathComponent("real.json")
        try Data("{}".utf8).write(to: realFile)
        try FileManager.default.createSymbolicLink(at: settingsFile, withDestinationURL: realFile)

        XCTAssertEqual(SetupHelper.preflight(at: settingsFile), .symlink)
    }

    func testPreflightDetectsMalformedJSON() throws {
        try Data("not json {".utf8).write(to: settingsFile)
        XCTAssertEqual(SetupHelper.preflight(at: settingsFile), .malformed)
    }

    func testPreflightDetectsUnexpectedStatusLineShape() throws {
        // statusLine is a String, not a dict
        try writeJSON(["statusLine": "echo hi"])
        XCTAssertEqual(SetupHelper.preflight(at: settingsFile), .unexpectedFormat)
    }

    func testPreflightDetectsStatusLineWithoutCommandString() throws {
        // statusLine is a dict but `command` is missing/non-String
        try writeJSON(["statusLine": ["type": "command", "command": 42]])
        XCTAssertEqual(SetupHelper.preflight(at: settingsFile), .unexpectedFormat)
    }

    func testPreflightAcceptsValidStatusLine() throws {
        try writeJSON(["statusLine": ["type": "command", "command": "echo"]])
        XCTAssertNil(SetupHelper.preflight(at: settingsFile))
    }

    func testPreflightAcceptsFileWithoutStatusLine() throws {
        try writeJSON(["other": "value"])
        XCTAssertNil(SetupHelper.preflight(at: settingsFile))
    }

    // MARK: - injectTee

    func testInjectTeeCreatesFileWhenMissing() {
        XCTAssertEqual(SetupHelper.injectTee(at: settingsFile), .success)

        let json = readJSON()
        let sl = json?["statusLine"] as? [String: Any]
        XCTAssertEqual(sl?["command"] as? String, SetupHelper.teeFragment)
        XCTAssertEqual(sl?["type"] as? String, "command")
    }

    func testInjectTeePrependsToExistingCommand() throws {
        try writeJSON([
            "statusLine": ["type": "command", "command": "powerline-statusline"]
        ])

        XCTAssertEqual(SetupHelper.injectTee(at: settingsFile), .success)

        let cmd = (readJSON()?["statusLine"] as? [String: Any])?["command"] as? String
        XCTAssertEqual(cmd, "\(SetupHelper.teeFragment) | powerline-statusline")
    }

    func testInjectTeeIsIdempotent() throws {
        try writeJSON([
            "statusLine": ["type": "command",
                           "command": "\(SetupHelper.teeFragment) | echo"]
        ])

        XCTAssertEqual(SetupHelper.injectTee(at: settingsFile), .success)

        // Cmd should remain unchanged (not double-wrapped)
        let cmd = (readJSON()?["statusLine"] as? [String: Any])?["command"] as? String
        XCTAssertEqual(cmd, "\(SetupHelper.teeFragment) | echo")
    }

    func testInjectTeePreservesUnknownStatusLineKeys() throws {
        try writeJSON([
            "statusLine": [
                "type": "command",
                "command": "echo",
                "futureKey": "do-not-drop",
            ],
            "topLevel": "stays",
        ])

        XCTAssertEqual(SetupHelper.injectTee(at: settingsFile), .success)

        let json = readJSON()
        let sl = json?["statusLine"] as? [String: Any]
        XCTAssertEqual(sl?["futureKey"] as? String, "do-not-drop")
        XCTAssertEqual(json?["topLevel"] as? String, "stays")
    }

    func testInjectTeeFailsOnMalformedFile() throws {
        try Data("garbage".utf8).write(to: settingsFile)
        XCTAssertEqual(SetupHelper.injectTee(at: settingsFile), .failed(.malformed))
    }

    func testInjectTeeWritesBackupFile() throws {
        try writeJSON(["statusLine": ["type": "command", "command": "echo"]])

        XCTAssertEqual(SetupHelper.injectTee(at: settingsFile), .success)

        let backups = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            .filter { $0.hasPrefix("settings.json.bak-") }
        XCTAssertFalse(backups.isEmpty, "expected at least one backup file")
    }

    // MARK: - uninstallHook

    func testUninstallHookReturnsFalseWhenNoHookPresent() throws {
        try writeJSON(["statusLine": ["type": "command", "command": "echo"]])
        XCTAssertFalse(SetupHelper.uninstallHook(at: settingsFile))
    }

    func testUninstallHookReturnsFalseWhenFileMissing() {
        XCTAssertFalse(SetupHelper.uninstallHook(at: settingsFile))
    }

    func testUninstallHookRemovesStatusLineWhenOnlyTee() throws {
        try writeJSON([
            "statusLine": ["type": "command", "command": SetupHelper.teeFragment]
        ])

        XCTAssertTrue(SetupHelper.uninstallHook(at: settingsFile))

        XCTAssertNil(readJSON()?["statusLine"])
    }

    func testUninstallHookKeepsExistingCommandAfterTee() throws {
        try writeJSON([
            "statusLine": ["type": "command",
                           "command": "\(SetupHelper.teeFragment) | powerline-statusline"]
        ])

        XCTAssertTrue(SetupHelper.uninstallHook(at: settingsFile))

        let cmd = (readJSON()?["statusLine"] as? [String: Any])?["command"] as? String
        XCTAssertEqual(cmd, "powerline-statusline")
    }

    // MARK: - cleanupBackups

    func testCleanupBackupsKeepsOnlyMostRecentN() throws {
        try writeJSON(["statusLine": ["type": "command", "command": "echo"]])

        // Create 6 fake backup files with different (sortable) names
        for i in 0..<6 {
            let backup = tempDir.appendingPathComponent("settings.json.bak-\(1_700_000_000 + i)")
            try Data("backup \(i)".utf8).write(to: backup)
        }

        SetupHelper.cleanupBackups(at: settingsFile, keeping: 3)

        let backups = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            .filter { $0.hasPrefix("settings.json.bak-") }
            .sorted()

        XCTAssertEqual(backups.count, 3)
        // Should keep the 3 with the highest timestamps (1_700_000_003 .. 5)
        XCTAssertEqual(backups, [
            "settings.json.bak-1700000003",
            "settings.json.bak-1700000004",
            "settings.json.bak-1700000005",
        ])
    }

    // MARK: - helpers

    private func writeJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: settingsFile)
    }

    private func readJSON() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }
}

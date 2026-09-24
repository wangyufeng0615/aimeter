import AppKit
import SwiftUI
import XCTest
@testable import AIMeter

final class DetailViewLayoutTests: XCTestCase {
    @MainActor
    func testEmptyRateCardsRenderWithAlignedHeaders() throws {
        let defaults = UserDefaults.standard
        let keys = [AppPaths.Keys.claudeRoot, AppPaths.Keys.codexRoot, "language"]
        let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("aimeter-layout-\(UUID().uuidString)", isDirectory: true)
        let claude = fixture.appendingPathComponent("claude", isDirectory: true)
        let codex = fixture.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        defer {
            for (key, value) in previous {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            try? FileManager.default.removeItem(at: fixture)
        }
        defaults.set(claude.path, forKey: AppPaths.Keys.claudeRoot)
        defaults.set(codex.path, forKey: AppPaths.Keys.codexRoot)
        defaults.set("en", forKey: "language")

        let store = UsageStore(autoload: false, autoRefresh: false, pricingLoader: {})
        store.claudeRateStatus = .rateLimitsUnavailable
        store.isLoading = false
        let renderer = ImageRenderer(content: DetailView(store: store)
            .environment(\.colorScheme, .light)
            .background(Color.white))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, 320)

        // Find the two dark service-name lines in the upper half of the
        // rendered menu. The gray empty-state text and wordmark are excluded.
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation ?? Data()))
        var headerLeftEdges: [Int] = []
        var activeLineLeft: Int?
        var blankRows = 0
        for y in 60..<min(280, bitmap.pixelsHigh) {
            let darkXs = (0..<min(400, bitmap.pixelsWide)).filter { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    return false
                }
                return color.redComponent < 0.35 && color.greenComponent < 0.35
                    && color.blueComponent < 0.35
            }
            if darkXs.count >= 8, let first = darkXs.first {
                activeLineLeft = min(activeLineLeft ?? first, first)
                blankRows = 0
            } else if let left = activeLineLeft {
                blankRows += 1
                if blankRows > 3 {
                    headerLeftEdges.append(left)
                    activeLineLeft = nil
                    blankRows = 0
                }
            }
        }
        if let left = activeLineLeft { headerLeftEdges.append(left) }
        guard headerLeftEdges.count >= 2 else {
            XCTFail("Expected both service headings in the rendered rate section")
            return
        }
        XCTAssertLessThanOrEqual(abs(headerLeftEdges[0] - headerLeftEdges[1]), 3,
                                 "Claude Code and Codex headings should share a left edge")
    }
}

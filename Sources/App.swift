import SwiftUI
import AppKit

@main
struct AIMeterApp: App {
    @StateObject private var store = UsageStore()
    @StateObject private var imageCache = StackedImageCache()
#if canImport(Sparkle)
    @StateObject private var updater = AppUpdater()
#endif
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        SetupHelper.checkOnLaunch()
    }

    var body: some Scene {
        MenuBarExtra {
            DetailView(store: store)
#if canImport(Sparkle)
                .environmentObject(updater)
#endif
        } label: {
            HStack(spacing: 3) {
                let items = store.menuBarItems
                if items.count > 1, let image = imageCache.image(items: items) {
                    Image(nsImage: image)
                } else {
                    Text(items.first ?? "—")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
#if canImport(Sparkle)
                if updater.pendingUpdateVersion != nil {
                    Image(systemName: "arrow.down.circle.fill")
                        .accessibilityLabel(S.updateAvailable)
                }
#endif
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
#if canImport(Sparkle)
                .environmentObject(updater)
#endif
        }
        .windowResizability(.contentSize)
    }
}

/// Caches the rasterized menu-bar label so identical item lists skip the
/// ImageRenderer → SwiftUI layout → rasterize pipeline. The label
/// is re-evaluated every time @Published fields on the store change (every
/// 2 s with the new rate timer), so caching matters.
@MainActor
final class StackedImageCache: ObservableObject {
    private var cached: (items: [String], image: NSImage)?

    func image(items: [String]) -> NSImage? {
        if let c = cached, c.items == items {
            return c.image
        }
        guard let rendered = render(items: items) else { return nil }
        cached = (items, rendered)
        return rendered
    }

    /// Two rows fit the menu bar height; a third entry sits beside them.
    private func render(items: [String]) -> NSImage? {
        let view = HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { Text($0.element) }
            }
            ForEach(Array(items.dropFirst(2).enumerated()), id: \.offset) { Text($0.element) }
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundColor(.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}

/// Accessory mode + helper to toggle while Settings window is open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // When Settings window closes, return to accessory (hide Dock icon)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            // Heuristic: Settings windows are titled "Settings" (or localized form)
            // and have standard window level. MenuBarExtra popover has a special level.
            guard window.level == .normal, window.styleMask.contains(.titled) else { return }
            Task { @MainActor in
                Self.restoreAccessoryWhenNoRegularWindow()
            }
        }
    }

    @MainActor
    static func restoreAccessoryWhenNoRegularWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let anyRegularVisible = NSApp.windows.contains { w in
                w.isVisible && w.level == .normal && w.styleMask.contains(.titled)
            }
            if !anyRegularVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// Settings opening is handled inside DetailView using
// @Environment(\.openSettings) — see `openSettingsFromMenuBar()` there.

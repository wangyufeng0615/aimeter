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
        } label: {
            if store.showCodex && UsageStore.claudeInstalled,
               let image = imageCache.image(
                   top: "Claude Code \(Int(store.claudePct))%",
                   bottom: "Codex \(Int(store.codexPct))%"
               ) {
                Image(nsImage: image)
            } else {
                Text(store.menuBarText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
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

/// Caches the rasterized menu-bar label so identical (top, bottom) inputs
/// skip the ImageRenderer → SwiftUI layout → rasterize pipeline. The label
/// is re-evaluated every time @Published fields on the store change (every
/// 2 s with the new rate timer), so caching matters.
@MainActor
final class StackedImageCache: ObservableObject {
    private var cached: (top: String, bottom: String, image: NSImage)?

    func image(top: String, bottom: String) -> NSImage? {
        if let c = cached, c.top == top, c.bottom == bottom {
            return c.image
        }
        guard let rendered = render(top: top, bottom: bottom) else { return nil }
        cached = (top, bottom, rendered)
        return rendered
    }

    private func render(top: String, bottom: String) -> NSImage? {
        let view = VStack(alignment: .trailing, spacing: 0) {
            Text(top)
            Text(bottom)
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
}

// Settings opening is handled inside DetailView using
// @Environment(\.openSettings) — see `openSettingsFromMenuBar()` there.

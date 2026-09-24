import Foundation

/// A ready update should wait until the menu/settings UI is out of use.
/// Kept independent of Sparkle so the timing policy can be tested by SwiftPM.
enum UpdateInstallPolicy {
    static let quietPeriod: TimeInterval = 30

    static func shouldInstall(readyAt: Date, now: Date,
                              hasVisibleInteractiveWindow: Bool) -> Bool {
        now.timeIntervalSince(readyAt) >= quietPeriod && !hasVisibleInteractiveWindow
    }
}

#if canImport(Sparkle)
import SwiftUI
import AppKit
import Sparkle

/// Owns Sparkle's update lifecycle and exposes its preferences and gentle
/// reminders to SwiftUI. Lives for the lifetime of the app.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    private var installTask: Task<Void, Never>?

    /// Disabled while Sparkle is already checking / downloading.
    @Published private(set) var canCheckForUpdates = false
    /// Mirror of SPUUpdater.automaticallyChecksForUpdates. Setting via
    /// `setAutomaticallyChecksForUpdates(_:)` writes through to Sparkle;
    /// Sparkle's KVO bounces the new value back here.
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var allowsAutomaticUpdates = false
    /// A scheduled update that needs the user's attention. Silent updates never set this.
    @Published private(set) var pendingUpdateVersion: String?

    override init() {
        super.init()
        // Both Sparkle delegates are weak. AppUpdater is retained by the App's
        // StateObject for the process lifetime, and owns the controller.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$automaticallyChecksForUpdates)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$automaticallyDownloadsUpdates)
        controller.updater.publisher(for: \.allowsAutomaticUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$allowsAutomaticUpdates)
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        controller.updater.automaticallyChecksForUpdates = value
    }

    func setAutomaticallyDownloadsUpdates(_ value: Bool) {
        controller.updater.automaticallyDownloadsUpdates = value
    }

    func showPendingUpdate() {
        // This is an explicit user action, so let Sparkle's window join the
        // regular app UI while the user reviews it.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: - Silent installation

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        // A menu-bar app may never quit. Take ownership of the ready update and
        // install it once no menu/settings window is being used. Sparkle still
        // installs on quit if the app exits first.
        installTask?.cancel()
        let readyAt = Date()
        installTask = Task { @MainActor in
            while !Task.isCancelled {
                if UpdateInstallPolicy.shouldInstall(
                    readyAt: readyAt, now: Date(),
                    hasVisibleInteractiveWindow: Self.hasVisibleInteractiveWindow
                ) {
                    immediateInstallHandler()
                    return
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
        return true
    }

    private static var hasVisibleInteractiveWindow: Bool {
        NSApp.windows.contains { window in
            window.isVisible && (window.isKeyWindow ||
                (window.level == .normal && window.styleMask.contains(.titled)))
        }
    }

    // MARK: - Gentle reminders for updates requiring user action

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                               andInImmediateFocus immediateFocus: Bool) -> Bool {
        // The default background alert is easy to miss in an LSUIElement app.
        // Ordinary updates wait behind a menu-bar indicator. Critical updates
        // retain Sparkle's standard prompt instead of waiting indefinitely.
        update.isCriticalUpdate
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if handleShowingUpdate && update.isCriticalUpdate && !state.userInitiated {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else if !handleShowingUpdate {
            pendingUpdateVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pendingUpdateVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingUpdateVersion = nil
        AppDelegate.restoreAccessoryWhenNoRegularWindow()
    }
}

/// Drop-in Settings section. Added to SettingsView only when Sparkle is
/// compiled in (i.e., real app builds, not `swift test`).
struct UpdatesSettingsSection: View {
    @EnvironmentObject private var updater: AppUpdater

    var body: some View {
        let autoBinding = Binding<Bool>(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.setAutomaticallyChecksForUpdates($0) }
        )
        let installBinding = Binding<Bool>(
            get: { updater.automaticallyDownloadsUpdates },
            set: { updater.setAutomaticallyDownloadsUpdates($0) }
        )

        return Group {
            Toggle(S.autoCheckUpdates, isOn: autoBinding)
            Toggle(S.autoInstallUpdates, isOn: installBinding)
                .disabled(!updater.allowsAutomaticUpdates)

            HStack {
                Button(S.checkForUpdates) {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                Spacer()
            }
        }
    }
}
#endif

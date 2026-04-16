#if canImport(Sparkle)
import Foundation
import SwiftUI
import Sparkle

/// Thin ObservableObject wrapper around SPUStandardUpdaterController so SwiftUI
/// views can observe Sparkle's `canCheckForUpdates` and bind to the
/// "automatically check" toggle. Lives for the lifetime of the app.
@MainActor
final class AppUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Disabled while Sparkle is already checking / downloading.
    @Published private(set) var canCheckForUpdates = false
    /// Mirror of SPUUpdater.automaticallyChecksForUpdates. Setting via
    /// `setAutomaticallyChecksForUpdates(_:)` writes through to Sparkle;
    /// Sparkle's KVO bounces the new value back here.
    @Published private(set) var automaticallyChecksForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$automaticallyChecksForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        controller.updater.automaticallyChecksForUpdates = value
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

        return Group {
            Toggle(S.autoCheckUpdates, isOn: autoBinding)

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

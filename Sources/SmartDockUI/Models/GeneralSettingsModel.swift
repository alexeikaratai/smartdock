import AppKit
import Observation
import SmartDockCore

// MARK: - General Settings Model

/// What the General tab shows and does: how the **app** behaves, as opposed to what the
/// Dock looks like, which belongs to a profile and lives on the Dock tab.
///
/// The split is not only about window height. "Launch at Login" is not a property of a
/// Dock profile, and reading it directly under a profile picker invited exactly that
/// misreading — more so once the picker starts naming display setups.
///
/// Every setting is read through an **explicit setter** rather than a settable property
/// the view binds straight into. A write can be refused — a login item macOS declines to
/// register, a notification permission the person says no to — and the answer has to come
/// from the system rather than from what was asked for. A settable property would need a
/// `didSet` that corrects itself, which is a write inside a write.
///
/// This is where the General tab's behaviour now lives, so it is tested without building
/// a view at all: `GeneralSettingsModelTests` asserts on this type, and the SwiftUI view
/// above it holds no logic to miss.
@MainActor
@Observable
final class GeneralSettingsModel {

    private(set) var launchesAtLogin: Bool
    private(set) var notificationsEnabled: Bool
    private(set) var syncsFromSystem: Bool

    @ObservationIgnored private let service: SmartDockService
    @ObservationIgnored private let prefs: UserPreferences
    @ObservationIgnored private let launchAtLogin: LaunchAtLogin
    /// Read from deinit to drop the observer above; `NotificationCenter` is `Sendable`,
    /// so it needs no `nonisolated(unsafe)` of its own.
    @ObservationIgnored private let events: NotificationCenter
    /// Quitting cannot be the real `NSApp.terminate` in a test — it would take the suite
    /// with it — so it is a parameter like every other call that leaves the process.
    @ObservationIgnored private let quitApp: @MainActor () -> Void
    /// Accessed from deinit (nonisolated) — must be nonisolated(unsafe), the same way
    /// `HotkeyManager` holds its event monitors.
    @ObservationIgnored private nonisolated(unsafe) var permissionObserver: (any NSObjectProtocol)?

    // MARK: - Init

    /// `events` is a parameter because the notification centre is process-wide: a shared
    /// one has every parallel suite hearing every other suite's posts, which is why
    /// `HotkeyManager` and `NotificationManager` take one too.
    init(
        service: SmartDockService,
        prefs: UserPreferences,
        launchAtLogin: LaunchAtLogin = LaunchAtLogin(),
        events: NotificationCenter = .default,
        quitApp: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        self.service = service
        self.prefs = prefs
        self.launchAtLogin = launchAtLogin
        self.events = events
        self.quitApp = quitApp

        launchesAtLogin = launchAtLogin.isEnabled
        notificationsEnabled = prefs.notificationsEnabled
        syncsFromSystem = prefs.syncFromSystemEnabled

        // Authorisation can be refused after the switch was turned on, which puts the
        // stored flag back off — the switch has to follow rather than go on claiming it
        // is on.
        permissionObserver = events.addObserver(
            forName: .smartDockNotificationPermissionChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.notificationsEnabled = self.prefs.notificationsEnabled
            }
        }
    }

    deinit {
        if let permissionObserver {
            events.removeObserver(permissionObserver)
        }
    }

    // MARK: - Intents

    /// Reads the result back rather than assuming the toggle took: macOS can refuse to
    /// register the login item, and a switch that flips anyway would claim something
    /// untrue until the window was reopened.
    func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != launchAtLogin.isEnabled else { return }
        launchAtLogin.toggle()
        launchesAtLogin = launchAtLogin.isEnabled
    }

    func setNotifications(_ enabled: Bool) {
        prefs.notificationsEnabled = enabled
        notificationsEnabled = enabled
        guard enabled else { return }
        events.post(name: .smartDockRequestNotificationAuth, object: nil)
    }

    func setSyncFromSystem(_ enabled: Bool) {
        prefs.syncFromSystemEnabled = enabled
        syncsFromSystem = enabled
    }

    func refreshNow() {
        service.refresh()
    }

    func quit() {
        quitApp()
    }
}

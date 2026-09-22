import Cocoa
import SmartDockCore
import UserNotifications

// MARK: - Notifications

extension Notification.Name {
    /// Posted when notification permission state changes (granted or denied).
    /// SettingsWindow observes this to revert the checkbox if permission is denied.
    static let smartDockNotificationPermissionChanged = Notification.Name(
        "com.smartdock.notificationPermissionChanged"
    )

    /// Posted by SettingsWindow to request notification authorization.
    static let smartDockRequestNotificationAuth = Notification.Name(
        "com.smartdock.requestNotificationAuth"
    )
}

// MARK: - Notification Center Seam

/// The slice of `UNUserNotificationCenter` the manager needs. Injectable for a
/// harder reason than the other seams: `UNUserNotificationCenter.current()` aborts
/// any process without a bundle — the test runner included — so the real one is
/// reached only through `SystemNotificationCenter`, and only inside the app.
@MainActor
protocol NotificationPosting: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func post(title: String, body: String, identifier: String) async throws
}

/// The real thing, resolved on first use rather than at construction.
@MainActor
final class SystemNotificationCenter: NotificationPosting {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func post(title: String, body: String, identifier: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}

// MARK: - Notification Manager

/// Posts macOS banner notifications when SmartDock switches profiles.
/// Observes `.smartDockStateDidChange` — same pattern as SettingsWindow.
@MainActor
public final class NotificationManager: NSObject {

    /// Called when the user clicks a profile-switch banner.
    public var onNotificationClicked: (() -> Void)?

    private let prefs: UserPreferences
    private let center: any NotificationPosting
    /// Which `NotificationCenter` carries the app's own announcements. The default
    /// in the app; a private one per test, since the manager listens for *any*
    /// sender and parallel suites would otherwise hear each other's switches.
    private let events: NotificationCenter
    private var isAuthorized = false

    /// Owns both reasons to stay quiet — unchanged profile, and banners arriving
    /// faster than 3s apart. Lives in Core so the ordering between the two is
    /// covered by tests; see `ProfileSwitchAnnouncer`.
    private var announcer: ProfileSwitchAnnouncer

    // MARK: - Init

    public convenience override init() {
        self.init(center: SystemNotificationCenter())
    }

    init(
        center: any NotificationPosting,
        prefs: UserPreferences = .shared,
        cooldown: TimeInterval = 3.0,
        events: NotificationCenter = .default
    ) {
        self.center = center
        self.prefs = prefs
        self.events = events
        self.announcer = ProfileSwitchAnnouncer(cooldown: cooldown)
        super.init()

        events.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .smartDockStateDidChange,
            object: nil
        )
        events.addObserver(
            self,
            selector: #selector(handleAuthRequest),
            name: .smartDockRequestNotificationAuth,
            object: nil
        )
    }

    deinit {
        // `events` is a `let` reference the deinit may touch; `NotificationCenter`
        // is thread-safe, so no isolation hop is needed.
        events.removeObserver(self)
    }

    // MARK: - Authorization

    @objc private func handleAuthRequest(_ notification: Notification) {
        requestAuthorizationIfNeeded()
    }

    /// Request notification permission. Called lazily on first notification attempt.
    private func requestAuthorizationIfNeeded() {
        Task {
            do {
                let granted = try await center.requestAuthorization()
                isAuthorized = granted
                if !granted {
                    prefs.notificationsEnabled = false
                }
                Log.info("Notification permission: \(granted ? "granted" : "denied")")
            } catch {
                isAuthorized = false
                prefs.notificationsEnabled = false
                Log.error("Notification permission request failed: \(error)")
            }

            events.post(
                name: .smartDockNotificationPermissionChanged,
                object: nil
            )
        }
    }

    // MARK: - State Change Handler

    @objc private func handleStateChange(_ notification: Notification) {
        guard prefs.notificationsEnabled else { return }

        guard let userInfo = notification.userInfo,
            let profile = userInfo[SmartDockService.activeProfileKey] as? DockProfile
        else {
            return
        }

        // Announce only a real profile switch (External↔Built-in), not a settings
        // change within the same profile, and not faster than the cooldown.
        guard announcer.shouldAnnounce(profile: profile, at: Date()) else { return }

        postNotification(profile: profile)
    }

    // MARK: - Private

    private func postNotification(profile: DockProfile) {
        // Request authorization lazily on first use
        if !isAuthorized {
            checkAndPost(profile: profile)
            return
        }

        deliverNotification(profile: profile)
    }

    private func checkAndPost(profile: DockProfile) {
        Task {
            let status = await center.authorizationStatus()

            if status == .notDetermined {
                // Request authorization, then post the notification if granted.
                let granted = (try? await center.requestAuthorization()) ?? false
                isAuthorized = granted
                if !granted {
                    prefs.notificationsEnabled = false
                    events.post(
                        name: .smartDockNotificationPermissionChanged,
                        object: nil
                    )
                    return
                }
            } else {
                isAuthorized = status == .authorized
            }

            if isAuthorized {
                deliverNotification(profile: profile)
            }
        }
    }

    private func deliverNotification(profile: DockProfile) {
        Task {
            do {
                try await center.post(
                    title: "SmartDock",
                    body: "Switched to \(profile.displayName) profile",
                    identifier: "com.smartdock.profileSwitch")
            } catch {
                Log.error("Failed to post notification: \(error)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show banner even when app is in foreground (LSUIElement apps are always "in foreground").
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Clicking the banner opens Settings — the banner says the profile changed,
    /// so the obvious follow-up is seeing what it changed to.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run {
            Log.info("Notification clicked — opening Settings")
            onNotificationClicked?()
        }
    }
}

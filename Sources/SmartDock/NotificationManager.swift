import Cocoa
import UserNotifications
import SmartDockCore

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

// MARK: - Notification Manager

/// Posts macOS banner notifications when SmartDock switches profiles.
/// Observes `.smartDockStateDidChange` — same pattern as SettingsWindow.
@MainActor
final class NotificationManager: NSObject {

    private let prefs = UserPreferences.shared
    private var lastNotificationDate: Date?
    private let cooldown: TimeInterval = 3.0
    private var isAuthorized = false

    /// Tracks last notified external state to avoid spamming notifications
    /// when only profile settings change (not the actual profile).
    private var lastNotifiedExternal: Bool?

    // MARK: - Init

    override init() {
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .smartDockStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthRequest),
            name: .smartDockRequestNotificationAuth,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Authorization

    @objc private func handleAuthRequest(_ notification: Notification) {
        requestAuthorizationIfNeeded()
    }

    /// Request notification permission. Called lazily on first notification attempt.
    private func requestAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
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

            NotificationCenter.default.post(
                name: .smartDockNotificationPermissionChanged,
                object: nil
            )
        }
    }

    // MARK: - State Change Handler

    @objc private func handleStateChange(_ notification: Notification) {
        guard prefs.notificationsEnabled else { return }

        guard let userInfo = notification.userInfo,
              let hasExternal = userInfo[SmartDockService.hasExternalKey] as? Bool else {
            return
        }

        // Only notify on actual profile switch (External↔Built-in),
        // not on settings changes within the same profile.
        if let last = lastNotifiedExternal, last == hasExternal {
            return
        }
        lastNotifiedExternal = hasExternal

        // Cooldown: prevent spam during rapid connect/disconnect
        if let lastDate = lastNotificationDate,
           Date().timeIntervalSince(lastDate) < cooldown {
            return
        }

        postNotification(hasExternal: hasExternal)
    }

    // MARK: - Private

    private func postNotification(hasExternal: Bool) {
        // Request authorization lazily on first use
        if !isAuthorized {
            checkAndPost(hasExternal: hasExternal)
            return
        }

        deliverNotification(hasExternal: hasExternal)
    }

    private func checkAndPost(hasExternal: Bool) {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()

            if settings.authorizationStatus == .notDetermined {
                // Request authorization, then post the notification if granted.
                let center = UNUserNotificationCenter.current()
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                isAuthorized = granted
                if !granted {
                    prefs.notificationsEnabled = false
                    NotificationCenter.default.post(
                        name: .smartDockNotificationPermissionChanged,
                        object: nil
                    )
                    return
                }
            } else {
                isAuthorized = settings.authorizationStatus == .authorized
            }

            if isAuthorized {
                deliverNotification(hasExternal: hasExternal)
            }
        }
    }

    private func deliverNotification(hasExternal: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "SmartDock"
        content.body = hasExternal
            ? "Switched to External Monitor config"
            : "Switched to Built-in Only config"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.smartdock.profileSwitch",
            content: content,
            trigger: nil
        )

        lastNotificationDate = Date()

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.error("Failed to post notification: \(error)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show banner even when app is in foreground (LSUIElement apps are always "in foreground").
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

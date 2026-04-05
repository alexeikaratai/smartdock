import Cocoa
import UserNotifications
import SmartDockCore

// MARK: - App Delegate

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private let service = SmartDockService()
    private var notificationManager: NotificationManager!
    private var hotkeyManager: HotkeyManager!

    /// Explicit entry point for a menu bar app without storyboard/nib.
    /// The default @main behavior calls NSApplicationMain which expects
    /// a MainMenu.nib — this override sets up the run loop manually.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement = true in Info.plist already hides us from Dock.
        // Do NOT call NSApp.setActivationPolicy(.accessory) here —
        // it can cause the status item to disappear during launch.

        // Migrate old pixel-based preferences to scale format
        UserPreferences.shared.migrateIfNeeded()

        // Check Accessibility permission before starting
        AccessibilityChecker.checkAndPromptIfNeeded()

        // Hotkey manager: global keyboard shortcuts
        hotkeyManager = HotkeyManager(service: service)
        hotkeyManager.start()

        statusBarController = StatusBarController(service: service, hotkeyManager: hotkeyManager)

        // Notification manager: posts macOS banners on profile switch
        notificationManager = NotificationManager()
        UNUserNotificationCenter.current().delegate = notificationManager

        service.start()

        Log.info("SmartDock launched (v\(Bundle.main.shortVersion))")
    }

    /// Called when user re-opens the app (e.g. clicks icon in /Applications while already running).
    /// Opens Settings so the app is accessible even if the status bar icon isn't visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController.showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
        service.stop()
    }
}

// MARK: - Bundle Helpers

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

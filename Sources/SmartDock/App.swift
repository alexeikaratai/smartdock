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
    private var onboardingWindow: OnboardingWindow?
    private let updateWatcher = AppUpdateWatcher()

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

        // Prompt for Accessibility on first launch only.
        // Subsequent launches (including after Homebrew updates) won't re-prompt.
        // Accessibility is needed only for global hotkeys — core dock switching works without it.
        AccessibilityChecker.promptIfFirstLaunch()

        // Hotkey manager: global keyboard shortcuts
        hotkeyManager = HotkeyManager(service: service)
        hotkeyManager.start()

        statusBarController = StatusBarController(service: service, hotkeyManager: hotkeyManager)
        hotkeyManager.onOpenSettings = { [weak self] in
            self?.statusBarController.showSettings()
        }

        // Notification manager: posts macOS banners on profile switch
        notificationManager = NotificationManager()
        UNUserNotificationCenter.current().delegate = notificationManager

        service.start()

        // Watch for binary changes (e.g. Homebrew upgrade) and prompt to relaunch
        updateWatcher.start()

        // If user just did "Reset Permission", guide them through grant flow
        if UserPreferences.shared.pendingAccessibilityGrant {
            handlePendingAccessibilityGrant()
        }

        // Show onboarding on first launch
        if !UserPreferences.shared.hasSeenOnboarding {
            onboardingWindow = OnboardingWindow()
            onboardingWindow?.onComplete = { [weak self] in
                self?.statusBarController.showSettings()
                self?.onboardingWindow = nil
            }
            onboardingWindow?.show()
        }

        Log.info("SmartDock launched (v\(Bundle.main.shortVersion))")
    }

    /// Called when user re-opens the app (e.g. clicks icon in /Applications while already running).
    /// Opens Settings so the app is accessible even if the status bar icon isn't visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController.showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateWatcher.stop()
        hotkeyManager.stop()
        service.stop()
    }

    // MARK: - Pending Accessibility Grant Flow

    /// After "Reset Permission" relaunch:
    /// 1. Open Settings on Shortcuts tab so user sees the warning
    /// 2. Open System Settings → Privacy → Accessibility
    /// 3. Poll AXIsProcessTrusted; auto-relaunch when granted
    private func handlePendingAccessibilityGrant() {
        Log.info("Resuming Accessibility grant flow after reset")

        // Open Settings on Shortcuts tab
        statusBarController.showSettings(tab: .shortcuts)

        // Open System Settings → Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // Poll for permission grant — when true, clear flag and relaunch.
        // Timeout: 5 minutes (300 attempts × 1s) so we don't poll forever.
        schedulePermissionPoll(remainingAttempts: 300)
    }

    private func schedulePermissionPoll(remainingAttempts: Int) {
        guard remainingAttempts > 0 else {
            Log.info("Accessibility grant poll timed out — clearing pending flag")
            UserPreferences.shared.pendingAccessibilityGrant = false
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            guard UserPreferences.shared.pendingAccessibilityGrant else { return }

            if AccessibilityChecker.isGranted {
                Log.info("Accessibility granted — relaunching to pick up new permission state")
                UserPreferences.shared.pendingAccessibilityGrant = false
                AppRelauncher.relaunch(bundlePath: Bundle.main.bundlePath)
            } else {
                self.schedulePermissionPoll(remainingAttempts: remainingAttempts - 1)
            }
        }
    }
}

// MARK: - Bundle Helpers

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

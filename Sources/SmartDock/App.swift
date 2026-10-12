import Cocoa
import SmartDockCore
import SmartDockUI
import UserNotifications

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

    /// Holds commands that arrive before `applicationDidFinishLaunching` has built
    /// the managers, and releases them once it has. Both a `smartdock://` URL and
    /// an Apple Event can launch the app, so either can land here.
    private var commandQueue = PendingCommandQueue()

    /// Outlives `applicationDidFinishLaunching`: the grant is waited for asynchronously.
    private var grantWatcher: AccessibilityGrantWatcher?

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
        notificationManager.onNotificationClicked = { [weak self] in
            self?.statusBarController.showSettings()
        }
        UNUserNotificationCenter.current().delegate = notificationManager

        service.start()

        // Watch for binary changes (e.g. Homebrew upgrade) and prompt to relaunch
        updateWatcher.start()

        // If the person just used "Grant Access…", walk them through the grant. Held in a
        // property because the wait is asynchronous and the watcher must outlive this call.
        grantWatcher = AccessibilityGrantWatcher(
            showSettings: { [weak self] in self?.statusBarController.showSettings(tab: .shortcuts) })
        grantWatcher?.startIfPending()

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

        // Run anything that arrived via URL or Apple Event while we were starting up.
        drainPendingCommands()
    }

    /// Called when user re-opens the app (e.g. clicks icon in /Applications while already running).
    /// Opens Settings so the app is accessible even if the status bar icon isn't visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController.showSettings()
        return false
    }

    // MARK: - External Commands

    /// Single entry point for commands originating outside the app.
    ///
    /// `smartdock://` URLs and AppleScript both funnel through here and on into
    /// `HotkeyManager.perform`, so every input path — hotkey, URL, Apple Event —
    /// shares one implementation and cannot drift apart.
    func performCommand(_ command: URLCommand) {
        // The command may have launched the app, arriving before
        // applicationDidFinishLaunching built the managers. The queue holds it
        // rather than letting us unwrap a nil.
        let ready = commandQueue.submit(command)
        guard !ready.isEmpty else {
            Log.info("Command \(command.rawValue) arrived before launch finished — queued")
            return
        }

        for command in ready {
            run(command)
        }
    }

    private func run(_ command: URLCommand) {
        Log.info("External command: \(command.rawValue)")
        hotkeyManager.perform(HotkeyAction(command))
    }

    /// Handles `smartdock://` URLs — lets Raycast, Alfred, Shortcuts.app and plain
    /// `open` drive the app.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = URLCommand(url: url) else {
                Log.error("Ignoring unrecognised URL: \(url.absoluteString)")
                continue
            }
            performCommand(command)
        }
    }

    private func drainPendingCommands() {
        let queued = commandQueue.markReady()
        guard !queued.isEmpty else { return }

        Log.info("Running \(queued.count) command(s) queued during launch")
        for command in queued {
            run(command)
        }
    }

    // MARK: - Lifecycle

    func applicationWillTerminate(_ notification: Notification) {
        updateWatcher.stop()
        hotkeyManager.stop()
        service.stop()
    }

}

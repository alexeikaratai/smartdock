import Cocoa
import SmartDockCore

// MARK: - App Delegate

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private let service = SmartDockService()

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
        // Remove icon from Dock — we live only in the menu bar
        NSApp.setActivationPolicy(.accessory)

        // Check Accessibility permission before starting
        AccessibilityChecker.checkAndPromptIfNeeded()

        statusBarController = StatusBarController(service: service)
        service.start()

        Log.info("SmartDock launched (v\(Bundle.main.shortVersion))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.stop()
    }
}

// MARK: - Bundle Helpers

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

import Cocoa
import SmartDockCore

/// Checks and prompts for Accessibility permission.
/// SmartDock needs this to control Dock visibility via System Events (AppleScript).
@MainActor
enum AccessibilityChecker {

    // MARK: - Public

    /// Check permission and prompt if needed.
    /// Returns true if permission is granted.
    @discardableResult
    static func checkAndPromptIfNeeded() -> Bool {
        // Already granted — nothing to do
        if AXIsProcessTrusted() { return true }

        Log.info("Accessibility permission not granted — prompting user")

        // Show system trust dialog (adds SmartDock to the list with a checkbox)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            showPermissionAlert()
        }

        return trusted
    }

    // MARK: - Private

    private static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            SmartDock needs Accessibility permission to control \
            the Dock when monitors are connected or disconnected.

            Enable SmartDock in System Settings → Privacy & Security → Accessibility, \
            then the app will start working automatically.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

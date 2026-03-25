import Cocoa
import SmartDockCore

/// Checks and prompts for Accessibility permission on first launch.
/// SmartDock needs this to control Dock visibility via System Events (AppleScript).
@MainActor
enum AccessibilityChecker {

    /// Check if the app has Accessibility permission.
    /// If not — show an alert explaining why it's needed
    /// and open System Settings to the right page.
    static func checkAndPromptIfNeeded() {
        // AXIsProcessTrusted() returns true if already granted
        guard !AXIsProcessTrusted() else { return }

        Log.info("Accessibility permission not granted — prompting user")

        let alert = NSAlert()
        alert.messageText = "SmartDock Needs Accessibility Permission"
        alert.informativeText = """
            SmartDock uses Accessibility to control Dock visibility \
            when you connect or disconnect an external monitor.

            Please grant permission in System Settings → \
            Privacy & Security → Accessibility, then restart SmartDock.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    /// Prompt the system trust dialog (checkbox style).
    /// This also returns the current trust state.
    static func requestTrust() -> Bool {
        // "AXTrustedCheckOptionPrompt" is the underlying string value of
        // kAXTrustedCheckOptionPrompt. Using the literal avoids accessing
        // the global var, which Swift 6 flags as non-concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Private

    private static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

import Cocoa
import SmartDockCore

/// Checks Accessibility permission status.
/// Accessibility is needed only for global hotkeys (`NSEvent.addGlobalMonitorForEvents`).
/// Core functionality (dock switching via AppleScript) works without it.
@MainActor
enum AccessibilityChecker {

    // MARK: - Public

    /// Whether Accessibility permission is currently granted.
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the system trust dialog if permission is not granted.
    /// Only called on first launch — avoids re-prompting after Homebrew updates
    /// where ad-hoc re-signing resets the permission.
    static func promptIfFirstLaunch() {
        guard !UserPreferences.shared.hasPromptedAccessibility else { return }
        guard !AXIsProcessTrusted() else { return }

        UserPreferences.shared.hasPromptedAccessibility = true
        Log.info("First launch — prompting for Accessibility permission")

        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
    }
}

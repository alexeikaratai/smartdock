import Cocoa
import SmartDockCore

/// Checks Accessibility permission status.
/// Accessibility is needed only for global hotkeys (`NSEvent.addGlobalMonitorForEvents`).
/// Core functionality (dock switching via AppleScript) works without it.
@MainActor
public enum AccessibilityChecker {

    // MARK: - Public

    /// Whether Accessibility permission is currently granted.
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the system trust dialog if permission is not granted.
    /// Only called on first launch — avoids re-prompting after Homebrew updates
    /// where ad-hoc re-signing resets the permission.
    public static func promptIfFirstLaunch(prefs: UserPreferences = .shared) {
        promptIfFirstLaunch(prefs: prefs, isTrusted: { AXIsProcessTrusted() }, prompt: showSystemPrompt)
    }

    /// `isTrusted` and `prompt` are parameters because the system dialog cannot be
    /// dismissed from a test — and a test bundle is never trusted, so the granted
    /// branch would be unreachable otherwise.
    static func promptIfFirstLaunch(
        prefs: UserPreferences, isTrusted: () -> Bool, prompt: () -> Void
    ) {
        guard !prefs.hasPromptedAccessibility else { return }
        guard !isTrusted() else { return }

        prefs.hasPromptedAccessibility = true
        Log.info("First launch — prompting for Accessibility permission")

        prompt()
    }

    private static func showSystemPrompt() {
        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
    }
}

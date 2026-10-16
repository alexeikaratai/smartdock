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

    /// What System Settings calls this permission, so a message can name the pane the
    /// person is being sent to. macOS 27 renamed it — measured in the pane's own
    /// strings, where `SecurityPrivacyExtension`'s `ACCESSIBILITY` key reads
    /// "Device Control and Data Access". Only the wording moved: `AXIsProcessTrusted`,
    /// the `Accessibility` TCC service name and the `Privacy_Accessibility` deep link
    /// anchor are all unchanged, and each was checked on 27.0.1.
    /// The version is read from the running system rather than written as
    /// `#available(macOS 27, *)`, which would ask the compiler about a release its SDK
    /// may not know: releases are built by CI on Xcode 26 and this machine has only
    /// Xcode 27, so that spelling could not be checked where it has to hold. Nothing is
    /// being guarded here anyway — no API changed, only the wording — so a plain version
    /// comparison says what is meant and compiles under either toolchain.
    static var settingName: String {
        let renamed = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(renamed) else {
            return "Accessibility"
        }
        return "Device Control and Data Access"
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

    /// Puts SmartDock in the Accessibility list, where the person only has to switch it
    /// on. Nothing else does: `AXIsProcessTrusted()` only *reads*, so after a reset the
    /// list has no SmartDock row and opening the pane shows nothing to turn on. Every
    /// path that sends someone to that pane calls this first.
    public static func prompt() {
        showSystemPrompt()
    }

    private static func showSystemPrompt() {
        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
    }
}

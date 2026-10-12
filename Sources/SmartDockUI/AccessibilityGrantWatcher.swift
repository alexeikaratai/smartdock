import Cocoa
import SmartDockCore

// MARK: - Accessibility Grant Watcher

/// Walks a person through granting the permission after **Grant Access…** cleared the
/// entry and relaunched: show the Shortcuts tab, ask, open the list, then wait for the
/// switch to be flipped and relaunch so the hotkey monitors pick it up.
///
/// Asking is the step that matters and the one that cannot move: macOS lists an app only
/// for a process started *after* the reset, and `AXIsProcessTrusted()` — which is all the
/// wait does — only reads. Without the ask the pane opened on a list with no SmartDock
/// row to switch on.
///
/// This lived in `App.swift`, in the executable and outside the test bundle, so none of it
/// was covered — which is how the missing ask survived. Every call that leaves the process
/// is a parameter here, and so is the delay, so a test drives the whole wait without one.
@MainActor
public final class AccessibilityGrantWatcher {

    /// 300 tries a second apart — five minutes, after which the flag is dropped rather
    /// than left to make every future launch reopen Settings.
    public static let attemptBudget = 300

    private static let accessibilityPaneURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    private let prefs: UserPreferences
    private let showSettings: @MainActor () -> Void
    private let promptForTrust: @MainActor () -> Void
    private let openURL: @MainActor (URL) -> Void
    private let isGranted: @MainActor () -> Bool
    private let relaunch: @MainActor () -> Void
    private let afterOneSecond: @MainActor (@escaping @MainActor () -> Void) -> Void

    // MARK: - Init

    /// `showSettings` has no default: only the app knows how to open its own window, and
    /// a default that reached for it would make this type untestable again.
    public init(
        prefs: UserPreferences = .shared,
        showSettings: @escaping @MainActor () -> Void,
        promptForTrust: @escaping @MainActor () -> Void = { AccessibilityChecker.prompt() },
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        isGranted: @escaping @MainActor () -> Bool = { AccessibilityChecker.isGranted },
        relaunch: @escaping @MainActor () -> Void = {
            AppRelauncher.relaunch(bundlePath: Bundle.main.bundlePath)
        },
        afterOneSecond: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { MainActor.assumeIsolated(work) }
        }
    ) {
        self.prefs = prefs
        self.showSettings = showSettings
        self.promptForTrust = promptForTrust
        self.openURL = openURL
        self.isGranted = isGranted
        self.relaunch = relaunch
        self.afterOneSecond = afterOneSecond
    }

    // MARK: - Public

    /// Does nothing unless **Grant Access…** set the flag before relaunching.
    public func startIfPending() {
        guard prefs.pendingAccessibilityGrant else { return }
        Log.info("Resuming Accessibility grant flow after reset")

        showSettings()
        // Before the pane, never after: this is what puts SmartDock in the list.
        promptForTrust()
        if let url = URL(string: Self.accessibilityPaneURL) {
            openURL(url)
        }
        wait(remaining: Self.attemptBudget)
    }

    // MARK: - Private

    private func wait(remaining: Int) {
        guard remaining > 0 else {
            Log.info("Accessibility grant poll timed out — clearing pending flag")
            prefs.pendingAccessibilityGrant = false
            return
        }

        afterOneSecond { [weak self] in
            guard let self else { return }
            // Cleared while we waited — something else finished the flow, and carrying on
            // would relaunch the app under someone who never asked for it.
            guard prefs.pendingAccessibilityGrant else { return }

            guard isGranted() else {
                wait(remaining: remaining - 1)
                return
            }
            Log.info("Accessibility granted — relaunching to pick up new permission state")
            prefs.pendingAccessibilityGrant = false
            relaunch()
        }
    }
}

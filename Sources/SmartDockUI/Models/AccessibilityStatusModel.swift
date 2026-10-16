import AppKit
import Observation
import SmartDockCore

// MARK: - Accessibility Status Model

/// Whether SmartDock may use the permission global hotkeys need, and the one way to fix
/// it when it may not.
///
/// **One button, `Grant Access…`.** *Open System Settings* and *Reset Permission* made
/// the person pick between never-granted and gone-stale, a difference nothing on screen
/// can show, when clearing the entry serves both. It clears, sets
/// `pendingAccessibilityGrant` and relaunches; only on a failed clear does it ask from
/// this process and offer the manual command.
///
/// Reset exists because ad-hoc signing invalidates the grant on every rebuild or Homebrew
/// update, which leaves the checkbox switched on while hotkeys silently stop firing —
/// `AXIsProcessTrusted()` reports that honestly, so this says *not allowed* while System
/// Settings still shows a tick.
@MainActor
@Observable
final class AccessibilityStatusModel {

    private(set) var isGranted: Bool

    /// What System Settings calls the permission. macOS 27 renamed it, and sending
    /// someone to a pane under a word that pane no longer uses is worse than not naming
    /// it — see `AccessibilityChecker.settingName`.
    var settingName: String { AccessibilityChecker.settingName }

    @ObservationIgnored private let prefs: UserPreferences
    @ObservationIgnored private let readIsGranted: @MainActor () -> Bool
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    @ObservationIgnored private let promptForTrust: @MainActor () -> Void
    @ObservationIgnored private let resetPermission: @MainActor (String) -> Bool
    @ObservationIgnored private let relaunch: @MainActor () -> Void
    @ObservationIgnored private let reportFailure: @MainActor (String) -> Void

    private static let accessibilityPaneURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    // MARK: - Init

    init(
        prefs: UserPreferences = .shared,
        isGranted: @escaping @MainActor () -> Bool = { AccessibilityChecker.isGranted },
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        promptForTrust: @escaping @MainActor () -> Void = { AccessibilityChecker.prompt() },
        resetPermission: @escaping @MainActor (String) -> Bool = AccessibilityStatusModel.runTccutil,
        relaunch: @escaping @MainActor () -> Void = {
            AppRelauncher.relaunch(bundlePath: Bundle.main.bundlePath)
        },
        reportFailure: @escaping @MainActor (String) -> Void = AccessibilityStatusModel.reportWithAlert
    ) {
        self.prefs = prefs
        self.readIsGranted = isGranted
        self.openURL = openURL
        self.promptForTrust = promptForTrust
        self.resetPermission = resetPermission
        self.relaunch = relaunch
        self.reportFailure = reportFailure
        self.isGranted = isGranted()
    }

    // MARK: - Intents

    /// Back from System Settings, where the person may have just switched SmartDock on.
    /// The permission was read once per window before this existed, so the tab went on
    /// saying *Not allowed* over a grant given a moment earlier.
    func refresh() {
        isGranted = readIsGranted()
    }

    /// Clears the entry, then relaunches so the new process can ask — macOS lists an app
    /// again only for a process started after the reset, so asking from this one would
    /// put nothing in the list. Clearing first is what lets a single button serve both
    /// the never-granted case and the stale one.
    ///
    /// When the entry cannot be cleared there is still something worth doing: ask from
    /// here, which covers the never-granted case, and say what to run by hand for the
    /// other. No confirmation in front of any of it — the button names what it does and
    /// the line beside it says the app restarts.
    func grantAccess() {
        // Set the flag before anything else: the next launch opens the Shortcuts tab and
        // watches for the grant, and that must hold even if the reset fails.
        prefs.pendingAccessibilityGrant = true

        let bundleID = Bundle.main.bundleIdentifier ?? "com.smartdock.app"
        guard resetPermission(bundleID) else {
            requestAccess()
            reportFailure(bundleID)
            return
        }

        // `AppRelauncher` waits for this process to exit first, so the two never run in
        // parallel. The new process asks — see `AccessibilityGrantWatcher`.
        relaunch()
    }

    // MARK: - Private

    /// Puts SmartDock in the list and opens it. The prompt comes first and is the whole
    /// point: opening the pane alone shows a list SmartDock is not in.
    private func requestAccess() {
        promptForTrust()
        guard let url = URL(string: Self.accessibilityPaneURL) else { return }
        openURL(url)
    }

    // MARK: - System seams

    /// Runs `tccutil` as the person, not as an administrator. Measured on 27.0.1:
    /// `tccutil reset Accessibility <id>` succeeds at uid 501, so the
    /// `do shell script … with administrator privileges` this replaced was asking for a
    /// password macOS never wanted. The **service** is still spelled `Accessibility`
    /// however System Settings labels the pane — checked against `tccutil` itself.
    static func runTccutil(bundleID: String) -> Bool {
        // `tccutil reset Accessibility` with no bundle ID resets the permission for every
        // app on the Mac, so an empty one must never reach it.
        guard !bundleID.isEmpty else {
            Log.error("Refusing to reset Accessibility without a bundle ID")
            return false
        }

        let process = Process()
        // Absolute, for the same reason `LogExport` spells out `/usr/bin/log`.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.error("Failed to reset Accessibility: \(error)")
            return false
        }
        return process.terminationStatus == 0
    }

    /// Says what to run by hand when the reset did not go through. No `sudo`: the command
    /// needs none, and offering one invites a password the reset never wanted. A
    /// parameter because a modal alert cannot be dismissed from a test — worse, it hangs
    /// the suite, which is how this was found.
    static func reportWithAlert(bundleID: String) {
        let failAlert = NSAlert()
        failAlert.messageText = "Couldn't reset the permission"
        failAlert.informativeText = """
            Run this command in Terminal:

            tccutil reset Accessibility \(bundleID)
            """
        failAlert.runModal()
    }
}

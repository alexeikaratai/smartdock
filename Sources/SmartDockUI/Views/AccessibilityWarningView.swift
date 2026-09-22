import Cocoa
import SmartDockCore

// MARK: - Accessibility Warning

/// Yellow banner shown on the Shortcuts tab while Accessibility permission
/// is missing. Offers to open System Settings, or to reset the permission —
/// ad-hoc signing invalidates the grant on every rebuild or Homebrew update,
/// which leaves the checkbox on while hotkeys silently stop working.
@MainActor
final class AccessibilityWarningView: NSView {

    private let prefs: UserPreferences
    /// Everything this banner does leaves the app: opening System Settings, asking
    /// for confirmation, running `tccutil` as an administrator, relaunching. Each is
    /// a parameter so the flow around them can be tested without doing any of it.
    private let openURL: @MainActor (URL) -> Void
    private let confirmReset: @MainActor () -> Bool
    private let resetPermission: @MainActor (String) -> Bool
    private let relaunch: @MainActor () -> Void
    private let reportFailure: @MainActor (String) -> Void
    private static let accessibilityPaneURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    // MARK: - Init

    init(
        prefs: UserPreferences = .shared,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        confirmReset: @escaping @MainActor () -> Bool = AccessibilityWarningView.confirmWithAlert,
        resetPermission: @escaping @MainActor (String) -> Bool = AccessibilityWarningView.runTccutil,
        relaunch: @escaping @MainActor () -> Void = {
            AppRelauncher.relaunch(bundlePath: Bundle.main.bundlePath)
        },
        reportFailure: @escaping @MainActor (String) -> Void = AccessibilityWarningView.reportWithAlert
    ) {
        self.prefs = prefs
        self.openURL = openURL
        self.confirmReset = confirmReset
        self.resetPermission = resetPermission
        self.relaunch = relaunch
        self.reportFailure = reportFailure
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = AccessibilityChecker.isGranted
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("AccessibilityWarningView is built programmatically — init(coder:) is unavailable")
    }

    // MARK: - Private

    private func buildUI() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.15).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.4).cgColor

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        icon.contentTintColor = .systemYellow
        addSubview(icon)

        let title = UI.label(
            "Hotkeys require Accessibility permission",
            font: .systemFont(ofSize: 12, weight: .medium))
        addSubview(title)

        let subtitle = UI.label(
            """
            If the checkbox is on but hotkeys still don't work, the permission is broken \
            (common after Homebrew updates). Use Reset to fix it.
            """,
            font: .systemFont(ofSize: 11)
        )
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 0
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.preferredMaxLayoutWidth = 340
        addSubview(subtitle)

        let openButton = UI.smallButton(
            "Open System Settings", target: self,
            action: #selector(openAccessibilitySettings))
        addSubview(openButton)

        let resetButton = UI.smallButton(
            "Reset Permission", target: self,
            action: #selector(resetAccessibilityPermission))
        addSubview(resetButton)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            title.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            openButton.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 8),
            openButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            openButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            resetButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
            resetButton.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 8),
        ])
    }

    // MARK: - Actions

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: Self.accessibilityPaneURL) else { return }
        openURL(url)
    }

    /// The app's confirmation: a modal alert.
    static func confirmWithAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Reset Accessibility Permission?"
        alert.informativeText = """
            This will remove SmartDock from the Accessibility list and restart the app. \
            You'll be prompted to grant permission again. Administrator password is required.
            """
        alert.addButton(withTitle: "Reset & Restart")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Runs `tccutil` behind an administrator prompt. Returns whether it succeeded.
    static func runTccutil(bundleID: String) -> Bool {
        let script = """
            do shell script "/usr/bin/tccutil reset Accessibility \(bundleID)" with administrator privileges
            """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            Log.error("Failed to reset Accessibility: \(error)")
            return false
        }
        return true
    }

    @objc private func resetAccessibilityPermission() {
        guard confirmReset() else { return }

        // Set the flag before anything else: the next launch opens the Shortcuts tab
        // and watches for the grant, and that must hold even if the reset fails.
        prefs.pendingAccessibilityGrant = true

        let bundleID = Bundle.main.bundleIdentifier ?? "com.smartdock.app"
        guard resetPermission(bundleID) else {
            reportFailure(bundleID)
            return
        }

        // Relaunch so the system re-checks the permission. `AppRelauncher` waits for
        // this process to exit first, so the two never run in parallel.
        relaunch()
    }

    /// Says what to run by hand when the privileged reset did not go through.
    /// A parameter for the same reason the confirmation is: a modal alert cannot be
    /// dismissed from a test, and this one hung the suite until it was seamed.
    static func reportWithAlert(bundleID: String) {
        let failAlert = NSAlert()
        failAlert.messageText = "Reset Failed"
        failAlert.informativeText = """
            Could not reset Accessibility permission. You can run this command manually:

            sudo tccutil reset Accessibility \(bundleID)
            """
        failAlert.runModal()
    }
}

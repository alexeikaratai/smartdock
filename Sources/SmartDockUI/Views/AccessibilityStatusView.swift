import Cocoa
import SmartDockCore

// MARK: - Accessibility Status

/// The permission row on the Shortcuts tab: what System Settings calls the permission,
/// whether SmartDock has it, and — only while it is missing — the two ways to fix that.
///
/// The row is built in **both** cases, and that is the point. This view used to build
/// nothing at all once the permission was there, because a hidden view still takes up
/// whatever height its contents ask for and the tab pins its rows below this one, which
/// left a blank band where the banner would have been. One short row costs about what
/// that band did and answers the question the band could not: whether hotkeys are
/// allowed to work at all, without a trip to System Settings to find out.
///
/// Reset exists because ad-hoc signing invalidates the grant on every rebuild or
/// Homebrew update, which leaves the checkbox switched on while hotkeys silently stop
/// firing — `AXIsProcessTrusted()` reports that honestly, so this view says *not
/// allowed* while System Settings still shows a tick.
@MainActor
final class AccessibilityStatusView: NSView {

    private let prefs: UserPreferences
    /// Settable, because the answer changes under an open window — see `refresh(isGranted:)`.
    private var isGranted: Bool
    /// Everything this view does leaves the app: opening System Settings, asking for
    /// confirmation, running `tccutil`, relaunching. Each is a parameter so the flow
    /// around them can be tested without doing any of it.
    private let openURL: @MainActor (URL) -> Void
    private let promptForTrust: @MainActor () -> Void
    private let resetPermission: @MainActor (String) -> Bool
    private let relaunch: @MainActor () -> Void
    private let reportFailure: @MainActor (String) -> Void
    private static let accessibilityPaneURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// The granted row carries no card, so it only needs enough inset to line its text
    /// up with the tab's other rows; the card around the warning needs its own padding.
    private var horizontalInset: CGFloat { isGranted ? 4 : 12 }
    private var verticalInset: CGFloat { isGranted ? 2 : 12 }

    // MARK: - Init

    init(
        prefs: UserPreferences = .shared,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        promptForTrust: @escaping @MainActor () -> Void = { AccessibilityChecker.prompt() },
        resetPermission: @escaping @MainActor (String) -> Bool = AccessibilityStatusView.runTccutil,
        relaunch: @escaping @MainActor () -> Void = {
            AppRelauncher.relaunch(bundlePath: Bundle.main.bundlePath)
        },
        reportFailure: @escaping @MainActor (String) -> Void = AccessibilityStatusView.reportWithAlert,
        isGranted: @autoclosure () -> Bool = AccessibilityChecker.isGranted
    ) {
        self.prefs = prefs
        self.openURL = openURL
        self.promptForTrust = promptForTrust
        self.resetPermission = resetPermission
        self.relaunch = relaunch
        self.reportFailure = reportFailure
        self.isGranted = isGranted()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("AccessibilityStatusView is built programmatically — init(coder:) is unavailable")
    }

    // MARK: - Public

    /// Rebuilds the row for a permission that changed while the window stayed open —
    /// someone reading *Not allowed*, switching SmartDock on in System Settings and
    /// coming back. Measured before this existed: the permission was read once per
    /// window, so the row went on saying *Not allowed* until the window was closed.
    ///
    /// The view itself stays put and only its contents are replaced. The Shortcuts tab
    /// chains its hotkey rows off this view's bottom anchor, so swapping the view for a
    /// new one would take those constraints with it.
    func refresh(isGranted: Bool) {
        guard isGranted != self.isGranted else { return }
        self.isGranted = isGranted

        for subview in subviews { subview.removeFromSuperview() }
        // The card's styling belongs to the warning, not to the view, and nothing else
        // would clear it on the way back to allowed.
        layer?.backgroundColor = nil
        layer?.borderWidth = 0
        buildUI()
    }

    // MARK: - Private

    private func buildUI() {
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(
            systemSymbolName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil)
        icon.contentTintColor = isGranted ? .systemGreen : .systemYellow
        addSubview(icon)

        // Named as System Settings names it, which macOS 27 changed — see
        // `AccessibilityChecker.settingName`. Sending someone to a pane under a word
        // that pane no longer uses is worse than not naming it.
        let title = UI.label(
            AccessibilityChecker.settingName, font: .systemFont(ofSize: 12, weight: .medium))
        addSubview(title)

        let status = UI.label(isGranted ? "Allowed" : "Not allowed", font: .systemFont(ofSize: 12))
        status.textColor = .secondaryLabelColor
        addSubview(status)

        // The name sits where every other row on the tab starts and the mark travels
        // with the word it qualifies, on the right. Leading the row with the icon
        // instead pushed the name 22pt clear of the shortcut labels under it.
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: verticalInset),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),

            status.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),

            icon.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            icon.trailingAnchor.constraint(equalTo: status.leadingAnchor, constant: -6),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            icon.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
        ])

        guard !isGranted else {
            // The row is the whole view: nothing to explain and nothing to fix.
            title.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalInset).isActive = true
            return
        }

        buildWarning(below: title)
    }

    /// The explanation and the one fix, shown only while the permission is missing.
    private func buildWarning(below title: NSTextField) {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.15).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.4).cgColor

        // One button, not two. "Open System Settings" and "Reset Permission" asked the
        // person to know which of their two problems they had — never granted, or granted
        // and then invalidated by an ad-hoc re-signing — when that difference is invisible
        // from outside and the second fix works for both. Granting clears the entry on the
        // way now, so one button covers either case.
        let subtitle = UI.label(
            """
            Global hotkeys need it. Grant Access restarts SmartDock and opens the list in \
            System Settings — switch SmartDock on there. An entry left behind by an update \
            is cleared on the way.
            """,
            font: .systemFont(ofSize: 11)
        )
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 0
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.preferredMaxLayoutWidth = 340
        addSubview(subtitle)

        let grantButton = UI.smallButton(
            "Grant Access…", target: self, action: #selector(grantAccess))
        addSubview(grantButton)

        NSLayoutConstraint.activate([
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),

            grantButton.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 8),
            grantButton.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            grantButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalInset),
        ])
    }

    // MARK: - Actions

    /// Puts SmartDock in the list and opens it. The prompt comes first and is the whole
    /// point: opening the pane alone shows a list SmartDock is not in, which is what the
    /// old "Open System Settings" button did after a reset had removed the entry.
    private func requestAccess() {
        promptForTrust()
        guard let url = URL(string: Self.accessibilityPaneURL) else { return }
        openURL(url)
    }

    /// Runs `tccutil` as the person, not as an administrator. Measured on 27.0.1:
    /// `tccutil reset Accessibility <id>` succeeds at uid 501, so the
    /// `do shell script … with administrator privileges` this replaced was asking for a
    /// password macOS never wanted. The **service** is still spelled `Accessibility`
    /// however System Settings labels the pane — checked against `tccutil` itself.
    static func runTccutil(bundleID: String) -> Bool {
        // `tccutil reset Accessibility` with no bundle ID resets the permission for
        // every app on the Mac, so an empty one must never reach it.
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

    /// Clears the entry, then relaunches so the new process can ask — macOS lists an app
    /// again only for a process started after the reset, so asking from this one would put
    /// nothing in the list. Clearing first is what lets a single button serve both the
    /// never-granted case and the stale one.
    ///
    /// When the entry cannot be cleared there is still something worth doing: ask from
    /// here, which covers the never-granted case, and say what to run by hand for the
    /// other. No confirmation in front of any of it — the button names what it does, the
    /// line above it says the app restarts, and a modal between a person and the thing
    /// they just asked for is friction, not safety.
    @objc private func grantAccess() {
        // Set the flag before anything else: the next launch opens the Shortcuts tab
        // and watches for the grant, and that must hold even if the reset fails.
        prefs.pendingAccessibilityGrant = true

        let bundleID = Bundle.main.bundleIdentifier ?? "com.smartdock.app"
        guard resetPermission(bundleID) else {
            requestAccess()
            reportFailure(bundleID)
            return
        }

        // `AppRelauncher` waits for this process to exit first, so the two never run in
        // parallel. The new process asks — see `handlePendingAccessibilityGrant`.
        relaunch()
    }

    /// Says what to run by hand when the reset did not go through. No `sudo`: the
    /// command needs none, and offering one invites a password the reset never wanted.
    /// A parameter because a modal alert cannot be dismissed from a test — worse, it
    /// hangs the suite, which is how this was found.
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

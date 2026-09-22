import Cocoa
import SmartDockCore

// MARK: - Dock Tab

/// Contents of the Settings window's Dock tab: the profile picker, the profile form,
/// the Use Current / Discard / Apply row, the refusal notice, Sync from System and the
/// status line. It owns the layout and reports every intent to the host through a
/// callback — it never applies, stores or asks anything itself. The draft rules
/// (what a tab switch, a profile switch or a close does to unsaved edits) stay in
/// `SettingsWindow`, because they involve the whole window, not this view.
///
/// Its height is defined from the inside — card top to status bottom — which is what
/// lets the host put it in a scroll view.
@MainActor
final class DockTabView: NSView {

    /// Which profile the form is editing. Also the segment order.
    enum Mode: Int, Sendable {
        case external = 0
        case builtin = 1

        var title: String {
            switch self {
            case .external: return "External Monitor"
            case .builtin: return "Built-in Only"
            }
        }

        var profile: DockProfile {
            switch self {
            case .external: .external
            case .builtin: .builtin
            }
        }

        init(_ profile: DockProfile) {
            switch profile {
            case .external: self = .external
            case .builtin: self = .builtin
            }
        }
    }

    // MARK: - Callbacks

    /// The person tapped a segment. The host decides whether the switch goes ahead —
    /// a dirty form asks first — and sets `selectedMode` back if it does not.
    var onModeChange: ((Mode) -> Void)?
    var onEdited: (() -> Void)?
    var onApply: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onUseCurrentDock: (() -> Void)?
    var onSyncFromSystem: (() -> Void)?

    // MARK: - State

    var selectedMode: Mode {
        get { Mode(rawValue: modeControl.selectedSegment) ?? .external }
        set { modeControl.selectedSegment = newValue.rawValue }
    }

    /// The form's contents. Setting it never counts as an edit.
    var configuration: DockConfiguration {
        get { profileForm.configuration }
        set { profileForm.configuration = newValue }
    }

    /// Whether the form holds unsaved edits — expressed as the two buttons that only
    /// make sense while it does.
    var isDirty: Bool {
        get { applyButton.isEnabled }
        set {
            applyButton.isEnabled = newValue
            discardButton.isEnabled = newValue
        }
    }

    /// A setting macOS refused, shown right under the button that asked for it.
    /// The same fact has been in the menu bar since 2.5.3, but that is not where a
    /// person is looking a second after pressing Apply.
    var refusalNotice: String? {
        didSet {
            refusalLabel.isHidden = refusalNotice == nil
            refusalLabel.stringValue = refusalNotice.map { "\u{26A0}\u{FE0F} \($0)" } ?? ""
        }
    }

    var status: String {
        get { statusLabel.stringValue }
        set { statusLabel.stringValue = newValue }
    }

    /// Marks the profile in force with ● on its segment. The status line says the
    /// same thing, but a person editing a profile looks at the picker.
    func markActive(_ mode: Mode) {
        for candidate in [Mode.external, .builtin] {
            let marker = candidate == mode ? "\u{25CF} " : ""
            modeControl.setLabel(marker + candidate.title, forSegment: candidate.rawValue)
        }
    }

    // MARK: - Controls

    /// Internal rather than private so a test can read a control's state back —
    /// whether Apply is enabled, which segment carries the marker — and click one.
    var modeControl: NSSegmentedControl!
    var applyButton: NSButton!
    var useCurrentButton: NSButton!
    var discardButton: NSButton!
    var syncButton: NSButton!
    var refusalLabel: NSTextField!
    private var profileForm: DockProfileForm!
    private var statusLabel: NSTextField!

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("DockTabView is built programmatically — init(coder:) is unavailable")
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        onModeChange?(selectedMode)
    }

    @objc private func apply(_ sender: Any) { onApply?() }
    @objc private func discard(_ sender: Any) { onDiscard?() }
    @objc private func useCurrentDock(_ sender: Any) { onUseCurrentDock?() }
    @objc private func syncFromSystem(_ sender: Any) { onSyncFromSystem?() }

    // MARK: - UI

    private func buildUI() {
        let margin: CGFloat = 24

        // Names what the control below actually does. Without it the segmented
        // control reads as a mode switch for the app rather than a choice of which
        // profile the form is editing.
        let editingLabel = UI.label("EDITING PROFILE", font: .systemFont(ofSize: 11, weight: .medium))
        editingLabel.textColor = .secondaryLabelColor

        // Mode control (External / Built-in). Segment titles are refreshed by
        // `markActive` so the active profile carries a marker.
        modeControl = NSSegmentedControl(
            labels: [Mode.external.title, Mode.builtin.title],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeChanged)
        )
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.selectedSegment = 0
        modeControl.segmentStyle = .automatic

        // Glass card — mode control goes inside as first element
        let card = UI.glassCard()
        addSubview(card)

        card.addSubview(editingLabel)
        card.addSubview(modeControl)

        // The profile controls live in the form; it reads and writes a
        // `DockConfiguration` through one binding table, so nothing here lists
        // the fields at all.
        profileForm = DockProfileForm()
        profileForm.onEdited = { [weak self] in self?.onEdited?() }
        card.addSubview(profileForm)

        applyButton = NSButton(title: "Apply", target: self, action: #selector(apply))
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.bezelStyle = .rounded
        applyButton.controlSize = .large
        applyButton.keyEquivalent = "\r"
        applyButton.isEnabled = false

        // Fills the form from the Dock as it is right now. Deliberately does not
        // apply anything: it seeds the fields and lights up Apply, so the change is
        // still the user's to confirm. Without it a profile has to be rebuilt from
        // scratch, control by control, even when the Dock is already set up the way
        // they want it saved.
        useCurrentButton = NSButton(
            title: "Use Current Dock", target: self, action: #selector(useCurrentDock))
        useCurrentButton.translatesAutoresizingMaskIntoConstraints = false
        useCurrentButton.bezelStyle = .rounded
        useCurrentButton.controlSize = .large

        // Reloads the stored profile and drops the draft. Until it existed the only
        // way out of an experiment was to close the window — which threw the draft
        // away silently — or to switch tabs, which applied it silently.
        discardButton = NSButton(title: "Discard", target: self, action: #selector(discard))
        discardButton.translatesAutoresizingMaskIntoConstraints = false
        discardButton.bezelStyle = .rounded
        discardButton.controlSize = .large
        discardButton.isEnabled = false

        // A stack so the three are laid out as one unit; their labels differ in width
        // and always will, so centring them individually cannot come out symmetrical.
        let buttonRow = NSStackView(views: [useCurrentButton, discardButton, applyButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        card.addSubview(buttonRow)

        refusalLabel = UI.label("", font: .systemFont(ofSize: 11))
        refusalLabel.textColor = .systemOrange
        refusalLabel.alignment = .center
        refusalLabel.isHidden = true
        card.addSubview(refusalLabel)

        // Stays with the profile it acts on: it writes the live Dock into whichever
        // mode is selected above, so separating it from that picker would leave a
        // button whose effect depends on a control on another tab.
        syncButton = UI.smallButton("Sync from System", target: self, action: #selector(syncFromSystem))
        addSubview(syncButton)

        statusLabel = UI.label("", font: .systemFont(ofSize: 11))
        statusLabel.textColor = .tertiaryLabelColor
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin - 4),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(margin - 4)),

            editingLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            editingLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            modeControl.topAnchor.constraint(equalTo: editingLabel.bottomAnchor, constant: 6),
            modeControl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            modeControl.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            profileForm.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 14),
            profileForm.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            profileForm.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            // Centred as a group, with Apply on the right where the confirming button
            // belongs. Pinning each button to `card.centerXAnchor` separately centres
            // the *gap* instead, which leaves a pair of unequal buttons visibly off to
            // one side — 20pt to the left, with these two labels.
            buttonRow.topAnchor.constraint(equalTo: profileForm.bottomAnchor, constant: 16),
            buttonRow.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            refusalLabel.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 8),
            refusalLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            refusalLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            refusalLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            applyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),

            syncButton.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 14),
            syncButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),

            statusLabel.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }
}

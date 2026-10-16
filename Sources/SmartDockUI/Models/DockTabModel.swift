import Observation
import SmartDockCore

// MARK: - Dock Tab Model

/// The Dock tab's state: which profile is being edited, the draft being edited, whether
/// it is dirty, what macOS refused and what the status line says.
///
/// It reports every intent to the host and **applies, stores and asks nothing itself**.
/// The draft rules — what a tab switch, a profile switch or a close does to unsaved
/// edits — stay in `SettingsWindow`, because they involve the whole window rather than
/// this tab.
///
/// Loading and editing are deliberately different doors. The host assigns
/// `configuration` to put a stored profile on screen, which is **not** an edit; the form
/// calls `edit(_:)`, which is. Until 2.6.2 those were the same path, and three routes
/// applied a draft silently while a fourth discarded one.
@MainActor
@Observable
final class DockTabModel {

    /// Which profile the form is editing. Also the segment order.
    enum Mode: Int, Sendable, CaseIterable, Identifiable {
        case external = 0
        case builtin = 1

        var id: Int { rawValue }

        /// The profile's name, from the one place that holds it. This used to be a
        /// second list: the tiles said "Built-in Only" while the menu, the tooltip, the
        /// banner, the diagnostic report and the Shortcuts action all said "Built-in
        /// Display" — one profile under two names, and nothing to notice it.
        var title: String { profile.displayName }

        /// What the display setup looks like. Two segments differing only in words made
        /// the picker read as a wall of text; a screen and a laptop are told apart
        /// without reading.
        var symbol: String {
            switch self {
            case .external: "display"
            case .builtin: "laptopcomputer"
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

    /// The segment the person has chosen. The host decides whether a change goes ahead —
    /// a dirty form asks first — and puts this back if it does not.
    var selectedMode: Mode = .external
    /// What the form shows. Assigning it is a load, never an edit.
    var configuration = DockConfiguration()
    /// Whether the form holds unsaved edits. Apply and Discard mean nothing without it.
    var isDirty = false
    /// A setting macOS refused, shown right under the button that asked for it. The same
    /// fact has been in the menu bar since 2.5.3, but that is not where a person is
    /// looking a second after pressing Apply.
    var refusalNotice: String?
    var status = ""
    /// The profile in force, marked with ● on its segment. The status line says the same
    /// thing, but a person editing a profile looks at the picker.
    var activeMode: Mode = .external

    // MARK: - Callbacks

    var onModeChange: ((Mode) -> Void)?
    var onEdited: (() -> Void)?
    var onApply: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onUseCurrentDock: (() -> Void)?
    var onSyncFromSystem: (() -> Void)?

    init() {}

    // MARK: - Intents

    /// An edit from the form: the draft moves and the host is told. Assigning
    /// `configuration` directly does neither, which is how a load stays a load.
    ///
    /// **A write that changes nothing is not an edit.** A SwiftUI `Slider` holds a
    /// continuous `Double` and writes back a value quantised to its own width, so merely
    /// drawing the Dock tab handed back a size a thousandth away from the stored one —
    /// enough to light up Apply and to make the next profile switch ask about a draft
    /// nobody had made. The comparison is the tolerant one for the same reason the Dock
    /// controller uses it: `sizeTolerance` is the step a person can actually choose.
    func edit(_ edited: DockConfiguration) {
        guard !edited.approximatelyEquals(configuration) else { return }
        configuration = edited
        onEdited?()
    }

    /// The person tapped a segment. Nothing moves until the host says so — it may have
    /// to ask about a draft first.
    func requestMode(_ mode: Mode) {
        guard mode != selectedMode else { return }
        onModeChange?(mode)
    }

    func markActive(_ mode: Mode) {
        activeMode = mode
    }

    /// Whether this profile is the one in force. Kept apart from `selectedMode` on
    /// purpose: a person can be **editing** Built-in while External is what the displays
    /// have chosen, and the two facts used to share one string — a ● glued in front of
    /// the name. One control carrying two independent facts is what made
    /// `activeProfile` and `hasExternalDisplay` easy to confuse in the first place.
    func isActive(_ mode: Mode) -> Bool {
        mode == activeMode
    }

    func apply() { onApply?() }
    func discard() { onDiscard?() }
    func useCurrentDock() { onUseCurrentDock?() }
    func syncFromSystem() { onSyncFromSystem?() }
}

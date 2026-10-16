import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

/// The Dock tab holds its state in a model and reports intent through callbacks; the host
/// owns the draft rules. These pin the contract between them — what the host sets is what
/// the tab shows, and what the person does is what the host hears.
///
/// Nothing here builds a view. The tab is SwiftUI now, and its controls read and write
/// this model; a test that clicked them would be testing SwiftUI, not SmartDock.
@Suite("Dock tab")
@MainActor
struct DockTabModelTests {

    @Test func dirtyStateDrivesApplyAndDiscard() {
        let model = DockTabModel()

        #expect(!model.isDirty, "a freshly loaded profile has nothing to apply")

        model.edit(DockConfiguration().with(autohide: true))

        // The model does not set this itself — the host does, on `onEdited`, because
        // only the host knows whether the edit differs from what is stored.
        model.isDirty = true
        #expect(model.isDirty)
    }

    /// The refusal line appears only while there is something to say, so a person never
    /// sees an empty orange gap under Apply.
    @Test func arefusalNoticeShowsAndClears() {
        let model = DockTabModel()

        #expect(model.refusalNotice == nil)

        model.refusalNotice = "Dock ignored autohide"
        #expect(model.refusalNotice == "Dock ignored autohide")

        model.refusalNotice = nil
        #expect(model.refusalNotice == nil)
    }

    /// Exactly one profile is in force, and it moves with the displays.
    @Test(arguments: [DockTabModel.Mode.external, .builtin])
    func exactlyOneProfileIsInForce(active: DockTabModel.Mode) {
        let model = DockTabModel()

        model.markActive(active)

        let inForce = DockTabModel.Mode.allCases.filter(model.isActive)
        #expect(inForce == [active], "in force: \(inForce), expected \(active)")
    }

    /// **Being edited and being in force are two different things**, and the tiles show
    /// them two different ways — a border for the first, a badge for the second. They
    /// used to share one string, a ● glued in front of the name, so a person editing
    /// Built-in while External applied could not tell at a glance.
    @Test func editingAprofileIsNotTheSameAsItBeingInForce() {
        let model = DockTabModel()
        model.markActive(.external)
        model.selectedMode = .builtin

        #expect(model.isActive(.external))
        #expect(!model.isActive(.builtin), "the profile being edited is not the one applying")
        #expect(model.selectedMode == .builtin)

        model.markActive(.builtin)
        #expect(model.isActive(.builtin), "the displays changed; the selection did not")
        #expect(model.selectedMode == .builtin)
    }

    /// **One profile, one name.** The tiles held their own words for a while: they said
    /// "Built-in Only" while the menu, the tooltip, the switch banner, the diagnostic
    /// report and the Shortcuts action all said "Built-in Display". Nothing disagreed
    /// loudly enough to notice — a second list, exactly the shape the Principles warn
    /// about — so the words now come from `DockProfile` and this says so.
    @Test(arguments: DockTabModel.Mode.allCases)
    func aprofileIsNamedTheSameEverywhere(mode: DockTabModel.Mode) {
        #expect(mode.title == mode.profile.displayName)
    }

    /// Each profile has its own picture, and both resolve. Two tiles differing only in
    /// words is what the segmented control already was.
    @Test(arguments: DockTabModel.Mode.allCases)
    func eachProfileHasItsOwnSymbol(mode: DockTabModel.Mode) {
        let others = DockTabModel.Mode.allCases.filter { $0 != mode }.map(\.symbol)

        #expect(
            NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil) != nil,
            "\(mode.symbol) does not resolve on this system")
        #expect(!others.contains(mode.symbol), "\(mode) shares its symbol with the other profile")
    }

    /// Choosing a profile is a *request*: the host may have to ask about a draft first,
    /// so nothing moves until it says so.
    @Test func selectingAmodeReportsItAndTheHostDecides() {
        let model = DockTabModel()
        var requested: [DockTabModel.Mode] = []
        model.onModeChange = { requested.append($0) }

        model.requestMode(.builtin)

        #expect(requested == [.builtin])
        #expect(model.selectedMode == .external, "the segment moved before the host agreed")

        model.selectedMode = .builtin
        #expect(model.selectedMode == .builtin)
    }

    /// Choosing the profile already shown is not a request — it would ask the host about
    /// a draft for a switch that changes nothing.
    @Test func reselectingTheSameModeAsksNothing() {
        let model = DockTabModel()
        var requested = 0
        model.onModeChange = { _ in requested += 1 }

        model.requestMode(.external)

        #expect(requested == 0)
    }

    /// An edit in the form reaches the host as `onEdited`; a configuration set *by* the
    /// host does not. Until 2.6.2 those were one path, and a load lit up Apply.
    @Test func editsPropagateButLoadsDoNot() {
        let model = DockTabModel()
        var edits = 0
        model.onEdited = { edits += 1 }

        model.configuration = DockConfiguration().with(autohide: true)
        model.configuration = DockConfiguration()
        #expect(edits == 0, "a load counted as an edit")

        model.edit(DockConfiguration().with(position: .left))
        #expect(edits == 1)
        #expect(model.configuration.position == .left, "the edit did not reach the draft")
    }

    /// A write that changes nothing is not an edit. A SwiftUI `Slider` holds a
    /// continuous `Double` and writes back a value quantised to its own width, so merely
    /// drawing the tab handed back a size a thousandth away from the stored one — which
    /// lit up Apply and made the next profile switch ask about a draft nobody had made.
    @Test func awriteThatChangesNothingIsNotAnEdit() {
        let model = DockTabModel()
        let stored = DockConfiguration(
            autohide: true, position: .bottom,
            iconSize: DockConfiguration.pixelsToScale(41),
            magnification: false,
            magnificationSize: DockConfiguration.pixelsToScale(94))
        model.configuration = stored
        var edits = 0
        model.onEdited = { edits += 1 }

        // What a slider hands back after rounding to its own pixel width.
        model.edit(stored.with(iconSize: stored.iconSize + 0.0009))
        #expect(edits == 0, "a size a thousandth away counted as an edit")

        // And the same configuration straight back.
        model.edit(stored)
        #expect(edits == 0)

        // A size a person can actually choose still counts.
        model.edit(stored.with(iconSize: DockConfiguration.pixelsToScale(64)))
        #expect(edits == 1, "a real change was swallowed")
    }

    @Test(arguments: ["apply", "discard", "useCurrentDock", "syncFromSystem"])
    func everyButtonReachesTheHost(button: String) {
        let model = DockTabModel()
        var heard: [String] = []
        model.onApply = { heard.append("apply") }
        model.onDiscard = { heard.append("discard") }
        model.onUseCurrentDock = { heard.append("useCurrentDock") }
        model.onSyncFromSystem = { heard.append("syncFromSystem") }

        switch button {
        case "apply": model.apply()
        case "discard": model.discard()
        case "useCurrentDock": model.useCurrentDock()
        default: model.syncFromSystem()
        }

        #expect(heard == [button])
    }
}

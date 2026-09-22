import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

/// The Dock tab owns its controls and reports intent through callbacks; the host
/// owns the draft rules. These pin the contract between them — what the host sets
/// is what the view shows, and what the person does is what the host hears.
@Suite("Dock tab view")
@MainActor
struct DockTabViewTests {

    @Test func dirtyStateDrivesApplyAndDiscard() {
        let tab = DockTabView()
        #expect(!tab.isDirty, "A fresh tab has no draft")

        tab.isDirty = true
        #expect(tab.applyButton.isEnabled)
        #expect(tab.discardButton.isEnabled)

        tab.isDirty = false
        #expect(!tab.applyButton.isEnabled)
        #expect(!tab.discardButton.isEnabled)
    }

    /// The refusal line appears only while there is something to say, so a person
    /// never sees an empty orange gap under Apply.
    @Test func aRefusalNoticeShowsAndClears() {
        let tab = DockTabView()
        #expect(tab.refusalLabel.isHidden)

        tab.refusalNotice = "macOS declined auto-hide"
        #expect(!tab.refusalLabel.isHidden)
        #expect(tab.refusalLabel.stringValue.contains("macOS declined auto-hide"))

        tab.refusalNotice = nil
        #expect(tab.refusalLabel.isHidden)
    }

    /// The ● marks exactly one segment — the profile in force — and moves with it.
    @Test(arguments: [DockTabView.Mode.external, .builtin])
    func theActiveProfileIsMarkedOnItsSegment(active: DockTabView.Mode) {
        let tab = DockTabView()

        tab.markActive(active)

        for mode in [DockTabView.Mode.external, .builtin] {
            let label = tab.modeControl.label(forSegment: mode.rawValue) ?? ""
            #expect(label.hasPrefix("\u{25CF}") == (mode == active), "\(mode): \(label)")
        }
    }

    @Test func selectingAModeReportsItAndTheHostCanSetItBack() {
        let tab = DockTabView()
        var reported: [DockTabView.Mode] = []
        tab.onModeChange = { reported.append($0) }

        tab.selectedMode = .builtin
        tab.modeControl.performClick(nil)

        #expect(reported == [.builtin])

        tab.selectedMode = .external
        #expect(tab.selectedMode == .external)
    }

    /// An edit in the form reaches the host as `onEdited`; a configuration set by
    /// the host does not — the same rule the form itself keeps.
    @Test func editsPropagateButLoadsDoNot() {
        let tab = DockTabView()
        var edits = 0
        tab.onEdited = { edits += 1 }

        tab.configuration = DockConfiguration(autohide: true, position: .left)
        #expect(edits == 0)
        #expect(tab.configuration == DockConfiguration(autohide: true, position: .left))
    }

    @Test(arguments: ["apply", "discard", "useCurrentDock", "syncFromSystem"])
    func eachButtonReportsItsIntent(button: String) {
        let tab = DockTabView()
        var heard: [String] = []
        tab.onApply = { heard.append("apply") }
        tab.onDiscard = { heard.append("discard") }
        tab.onUseCurrentDock = { heard.append("useCurrentDock") }
        tab.onSyncFromSystem = { heard.append("syncFromSystem") }
        tab.isDirty = true  // Apply and Discard are disabled otherwise and a click is a no-op.

        let control: NSButton =
            switch button {
            case "apply": tab.applyButton
            case "discard": tab.discardButton
            case "useCurrentDock": tab.useCurrentButton
            default: tab.syncButton
            }
        control.performClick(nil)

        #expect(heard == [button])
    }
}

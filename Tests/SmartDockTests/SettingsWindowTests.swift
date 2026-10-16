import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

/// The window is where the draft rules live: what a tab switch, a profile switch and
/// a close do to unsaved edits. The modal question is injected, so each answer can
/// be given from here.
@Suite("Settings window")
@MainActor
struct SettingsWindowTests {

    /// The answer the "Apply / Discard / Cancel" question will get, and how often it
    /// was asked — a stand-in for the person at the alert.
    @MainActor
    private final class Answers {
        var decision: SettingsWindow.DraftDecision = .cancel
        var questionsAsked = 0
    }

    @MainActor
    private final class Fixture {
        let scratch = ScratchPreferences()
        let monitor = MockDisplayMonitor()
        let dock = MockDockController()
        let service: SmartDockService
        let hotkeys: HotkeyManager
        let settings: SettingsWindow
        private let answers = Answers()

        var decision: SettingsWindow.DraftDecision {
            get { answers.decision }
            set { answers.decision = newValue }
        }
        var questionsAsked: Int { answers.questionsAsked }

        init(externalCount: Int = 1) {
            _ = NSApplication.shared  // `show` activates the app; there has to be one.
            scratch.prefs.externalConfig = DockConfiguration(autohide: false, position: .bottom)
            scratch.prefs.builtinConfig = DockConfiguration(autohide: true, position: .left)
            monitor.mockExternalCount = externalCount
            service = SmartDockService(displayMonitor: monitor, dockController: dock, prefs: scratch.prefs)
            service.start()
            hotkeys = HotkeyManager(
                service: service, prefs: scratch.prefs,
                // Private: the workspace centre is process-wide, and a real activation
                // mid-suite would have this manager install real event monitors.
                workspaceEvents: NotificationCenter())
            let answers = self.answers
            settings = SettingsWindow(
                service: service, hotkeyManager: hotkeys, prefs: scratch.prefs,
                decideDraft: { _ in
                    answers.questionsAsked += 1
                    return answers.decision
                })
        }

        /// Edits the form the way a person would — through the tab's own callback.
        func edit(_ config: DockConfiguration) {
            settings.dockTab.configuration = config
            settings.dockTab.onEdited?()
        }

        func close() { settings.window?.close() }
    }

    private func keyDown(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, _ char: String) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                context: nil, characters: char, charactersIgnoringModifiers: char, isARepeat: false,
                keyCode: keyCode))
    }

    // MARK: - Opening

    @Test func showOpensOnTheProfileInForceAndTheRequestedTab() {
        let f = Fixture(externalCount: 0)

        f.settings.show(tab: .shortcuts)

        #expect(f.settings.window?.isVisible == true)
        #expect(f.settings.selectedMode == .builtin)
        #expect(f.settings.currentTab == .shortcuts)
        #expect(f.settings.dockTab.configuration == f.scratch.prefs.builtinConfig)
        #expect(f.settings.dockTab.status == "Current: Built-in display only")
        f.close()
    }

    @Test func showingAgainSwitchesTheTabWithoutRebuildingTheWindow() {
        let f = Fixture()
        f.settings.show(tab: .dock)
        let window = f.settings.window

        f.settings.show(tab: .about)

        #expect(f.settings.window === window)
        #expect(f.settings.currentTab == .about)
        f.close()
    }

    @Test(arguments: [SettingsWindow.Tab.dock, .general, .shortcuts, .about])
    func exactlyOneTabIsVisible(tab: SettingsWindow.Tab) {
        let f = Fixture()
        f.settings.show(tab: tab)

        #expect(f.settings.settingsScroll.isHidden == (tab != .dock))
        #expect(f.settings.generalContainer.isHidden == (tab != .general))
        #expect(f.settings.shortcutsContainer.isHidden == (tab != .shortcuts))
        #expect(f.settings.aboutContainer.isHidden == (tab != .about))
        #expect(f.settings.tabControl.selectedSegment == tab.rawValue)
        f.close()
    }

    // MARK: - The Draft Rules

    /// A draft survives a tab switch untouched — no question, no apply, no discard.
    @Test func aDraftSurvivesATabSwitch() {
        let f = Fixture()
        f.settings.show(tab: .dock)
        let draft = DockConfiguration(autohide: true, position: .right)
        f.edit(draft)

        f.settings.show(tab: .general)
        f.settings.show(tab: .dock)

        #expect(f.settings.dockTab.isDirty)
        #expect(f.settings.dockTab.configuration == draft)
        #expect(f.questionsAsked == 0)
        #expect(f.scratch.prefs.externalConfig.position == .bottom, "nothing applied")
        f.close()
    }

    @Test func switchingProfilesWithoutADraftAsksNothing() {
        let f = Fixture(externalCount: 1)
        f.settings.show(tab: .dock)

        f.settings.dockTab.selectedMode = .builtin
        f.settings.dockTab.onModeChange?(.builtin)

        #expect(f.questionsAsked == 0)
        #expect(f.settings.selectedMode == .builtin)
        #expect(f.settings.dockTab.configuration == f.scratch.prefs.builtinConfig)
        f.close()
    }

    @Test func switchingProfilesWithADraftCanApplyIt() {
        let f = Fixture(externalCount: 1)
        f.settings.show(tab: .dock)
        f.edit(DockConfiguration(autohide: true, position: .right))
        f.decision = .apply

        f.settings.dockTab.selectedMode = .builtin
        f.settings.dockTab.onModeChange?(.builtin)

        #expect(f.questionsAsked == 1)
        #expect(f.scratch.prefs.externalConfig.position == .right, "the draft went to the profile it was edited on")
        #expect(f.settings.selectedMode == .builtin)
        #expect(!f.settings.dockTab.isDirty)
        f.close()
    }

    @Test func switchingProfilesWithADraftCanDiscardIt() {
        let f = Fixture(externalCount: 1)
        f.settings.show(tab: .dock)
        f.edit(DockConfiguration(autohide: true, position: .right))
        f.decision = .discard

        f.settings.dockTab.selectedMode = .builtin
        f.settings.dockTab.onModeChange?(.builtin)

        #expect(f.scratch.prefs.externalConfig.position == .bottom, "the draft is gone")
        #expect(f.settings.selectedMode == .builtin)
        f.close()
    }

    @Test func switchingProfilesWithADraftCanBeCancelled() {
        let f = Fixture(externalCount: 1)
        f.settings.show(tab: .dock)
        let draft = DockConfiguration(autohide: true, position: .right)
        f.edit(draft)
        f.decision = .cancel

        f.settings.dockTab.selectedMode = .builtin
        f.settings.dockTab.onModeChange?(.builtin)

        #expect(f.settings.selectedMode == .external, "the switch did not happen")
        #expect(f.settings.dockTab.selectedMode == .external, "and the picker was put back")
        #expect(f.settings.dockTab.configuration == draft, "the draft is still there")
        f.close()
    }

    @Test func closingWithADraftAsksAndCancelKeepsTheWindow() throws {
        let f = Fixture()
        f.settings.show(tab: .dock)
        f.edit(DockConfiguration(autohide: true, position: .right))
        f.decision = .cancel
        let window = try #require(f.settings.window)

        let mayClose = f.settings.windowShouldClose(window)

        #expect(!mayClose)
        #expect(f.questionsAsked == 1)
        f.close()
    }

    @Test func closingWithADraftCanApplyIt() throws {
        let f = Fixture()
        f.settings.show(tab: .dock)
        f.edit(DockConfiguration(autohide: true, position: .right))
        f.decision = .apply
        let window = try #require(f.settings.window)

        #expect(f.settings.windowShouldClose(window))
        #expect(f.scratch.prefs.externalConfig.position == .right)
        f.close()
    }

    @Test func closingWithoutADraftAsksNothing() throws {
        let f = Fixture()
        f.settings.show(tab: .dock)
        let window = try #require(f.settings.window)

        #expect(f.settings.windowShouldClose(window))
        #expect(f.questionsAsked == 0)
        f.close()
    }

    // MARK: - The Buttons

    @Test func applyStoresTheDraftAndReappliesTheProfileInForce() {
        let f = Fixture(externalCount: 1)
        f.settings.show(tab: .dock)
        f.edit(DockConfiguration(autohide: true, position: .right))

        f.settings.dockTab.onApply?()

        #expect(f.scratch.prefs.externalConfig == DockConfiguration(autohide: true, position: .right))
        #expect(f.dock.lastAppliedConfig?.position == .right, "the profile in force was re-applied")
        #expect(!f.settings.dockTab.isDirty)
        f.close()
    }

    /// Applying an edit to the *other* profile stores it but moves nothing.
    @Test func applyingTheOtherProfileDoesNotTouchTheDock() {
        let f = Fixture(externalCount: 1)
        f.settings.show(tab: .dock)
        f.settings.dockTab.selectedMode = .builtin
        f.settings.dockTab.onModeChange?(.builtin)
        f.edit(DockConfiguration(autohide: true, position: .right))
        let applies = f.dock.applyCallCount

        f.settings.dockTab.onApply?()

        #expect(f.scratch.prefs.builtinConfig.position == .right)
        #expect(f.dock.applyCallCount == applies)
        f.close()
    }

    @Test func discardReloadsTheStoredProfile() {
        let f = Fixture()
        f.settings.show(tab: .dock)
        f.edit(DockConfiguration(autohide: true, position: .right))

        f.settings.dockTab.onDiscard?()

        #expect(f.settings.dockTab.configuration == f.scratch.prefs.externalConfig)
        #expect(!f.settings.dockTab.isDirty)
        f.close()
    }

    /// Seeds the form from the live Dock and lights up Apply — nothing applied.
    @Test func useCurrentDockSeedsADraftFromTheLiveDock() {
        let f = Fixture()
        f.dock.mockSystemConfig = DockConfiguration(autohide: true, position: .left, showsRecents: false)
        f.settings.show(tab: .dock)

        f.settings.dockTab.onUseCurrentDock?()

        #expect(f.settings.dockTab.configuration == f.dock.mockSystemConfig)
        #expect(f.settings.dockTab.isDirty)
        #expect(f.scratch.prefs.externalConfig.position == .bottom, "still a draft")
        f.close()
    }

    @Test func syncFromSystemWritesTheLiveDockIntoTheSelectedProfile() {
        let f = Fixture()
        f.dock.mockSystemConfig = DockConfiguration(autohide: true, position: .left)
        f.settings.show(tab: .dock)

        f.settings.dockTab.onSyncFromSystem?()

        #expect(f.scratch.prefs.externalConfig == f.dock.mockSystemConfig)
        #expect(!f.settings.dockTab.isDirty)
        f.close()
    }

    // MARK: - Keys

    /// ⌘0 asks for the default size and swallows the keystroke. What the window ends
    /// up at is the window server's call — it clamps to the screen, and a CI runner's
    /// is smaller than the 420×720 this asks for — so only the request is asserted.
    @Test func commandZeroIsConsumedAndAsksForTheDefaultSize() throws {
        let f = Fixture()
        f.settings.show(tab: .dock)
        let window = try #require(f.settings.window)
        window.setContentSize(NSSize(width: 500, height: 800))

        let consumed = f.settings.handleKey(try keyDown(29, [.command], "0")) == nil

        #expect(consumed)
        #expect(window.contentView?.frame.size != NSSize(width: 500, height: 800))
        f.close()
    }

    @Test func escapeClosesTheWindowUnlessRecording() throws {
        let f = Fixture()
        f.settings.show(tab: .shortcuts)
        f.settings.hotkeyRecorder.start(.refreshNow)

        let passedThrough = f.settings.handleKey(try keyDown(53, [], "\u{1B}")) != nil
        #expect(passedThrough, "Escape belongs to the recorder while recording")
        f.settings.hotkeyRecorder.stop()

        #expect(f.settings.handleKey(try keyDown(53, [], "\u{1B}")) == nil)
        #expect(f.settings.window == nil, "closed")
    }

    // MARK: - Reacting to the App

    /// A state change while the window is open refreshes what it shows, but never
    /// touches a draft.
    @Test func aStateChangeRefreshesTheStatusButKeepsADraft() {
        let f = Fixture(externalCount: 1)
        f.settings.show(tab: .dock)
        let draft = DockConfiguration(autohide: true, position: .right)
        f.edit(draft)

        f.service.applyProfile(.builtin)

        #expect(f.settings.dockTab.status == "Current: Built-in profile · external monitor connected")
        #expect(f.settings.dockTab.configuration == draft)
        f.close()
    }

    @Test func leavingTheShortcutsTabCancelsARecording() {
        let f = Fixture()
        f.settings.show(tab: .shortcuts)
        f.settings.hotkeyRecorder.start(.refreshNow)

        f.settings.show(tab: .dock)

        #expect(!f.settings.hotkeyRecorder.isRecording)
        f.close()
    }

    /// The rows read their titles from stored bindings, and re-read them when the
    /// recorder finishes. The bindings live in `UserPreferences`, which is not
    /// observable, so nothing refreshes on its own.
    @Test func therowsShowTheirBindings() {
        let f = Fixture()
        f.scratch.prefs.setHotkey(
            HotkeyBinding(
                keyCode: 15, modifiers: NSEvent.ModifierFlags.control.rawValue, displayName: "R"),
            for: HotkeyAction.refreshNow.rawValue)

        f.settings.show(tab: .shortcuts)

        #expect(f.settings.shortcutsModel.title(for: .refreshNow).hasSuffix("R"))
        #expect(f.settings.shortcutsModel.title(for: .openSettings) == "Click to set")
        f.close()
    }

    /// Only the row being recorded says it is listening, and a second request stops the
    /// first: two recorders at once would each consume the same keystroke.
    @Test func onlyTherowBeingRecordedSaysSo() {
        let f = Fixture()
        f.settings.show(tab: .shortcuts)

        f.settings.shortcutsModel.record(.refreshNow)
        #expect(f.settings.hotkeyRecorder.isRecording)
        #expect(f.settings.shortcutsModel.title(for: .refreshNow) == "Press shortcut\u{2026}")
        #expect(f.settings.shortcutsModel.title(for: .openSettings) == "Click to set")

        f.settings.shortcutsModel.record(.openSettings)
        #expect(f.settings.shortcutsModel.title(for: .refreshNow) == "Click to set")
        #expect(f.settings.shortcutsModel.title(for: .openSettings) == "Press shortcut\u{2026}")

        f.settings.shortcutsModel.stopRecording()
        #expect(!f.settings.hotkeyRecorder.isRecording)
        f.close()
    }

    /// Choosing the other profile has to move the picker. An `NSSegmentedControl` moved
    /// itself on the click and the host only put it back when it refused; a SwiftUI
    /// `Picker` moves for nobody, so the host has to. Without this the form showed the
    /// built-in profile while the picker still claimed External, and switching back
    /// appeared to do nothing.
    @Test func acceptingAprofileSwitchMovesThePicker() {
        let f = Fixture()
        f.settings.show(tab: .dock)
        #expect(f.settings.dockTab.selectedMode == .external)

        f.settings.dockTab.requestMode(.builtin)

        #expect(f.settings.selectedMode == .builtin, "the window did not change profile")
        #expect(f.settings.dockTab.selectedMode == .builtin, "the picker stayed where it was")

        f.settings.dockTab.requestMode(.external)

        #expect(f.settings.selectedMode == .external, "switching back did nothing")
        #expect(f.settings.dockTab.selectedMode == .external)
        f.close()
    }

    /// And the form follows the picker: each profile's own settings, not the other's.
    @Test func switchingProfileShowsThatProfilesSettings() {
        let f = Fixture()
        f.scratch.prefs.externalConfig = DockConfiguration(autohide: true, position: .left)
        f.scratch.prefs.builtinConfig = DockConfiguration(autohide: false, position: .right)
        f.settings.show(tab: .dock)

        f.settings.dockTab.requestMode(.builtin)
        #expect(f.settings.dockTab.configuration.position == .right)
        #expect(!f.settings.dockTab.configuration.autohide)

        f.settings.dockTab.requestMode(.external)
        #expect(f.settings.dockTab.configuration.position == .left)
        #expect(f.settings.dockTab.configuration.autohide)
        f.close()
    }

    /// The segments come from `Tab.allCases`, not from a literal beside it. There were
    /// two lists for one set of tabs — a fifth could have appeared in the enum and not
    /// in the control, or the two could have fallen out of order, and nothing would
    /// have said so.
    @Test func thesegmentsAreTheTabs() {
        let f = Fixture()
        f.settings.show(tab: .dock)

        let labels = (0..<f.settings.tabControl.segmentCount).map {
            f.settings.tabControl.label(forSegment: $0) ?? ""
        }

        // The words, written down once. Comparing the control against
        // `allCases.map(\.title)` alone proves only that the two are wired together —
        // swap two titles in the enum and both sides swap with it, which is exactly
        // what a mutation showed.
        #expect(labels == ["Dock", "General", "Shortcuts", "About"], "the control reads \(labels)")
        #expect(
            labels == SettingsWindow.Tab.allCases.map(\.title),
            "the control and the enum disagree")
        f.close()
    }

    /// A segment's position **is** its `rawValue` — `tabChanged` reads the selected
    /// index straight back into a `Tab`, so an enum reordered without the control
    /// would open the wrong page.
    @Test func eachsegmentIndexIsItsTab() {
        let f = Fixture()
        f.settings.show(tab: .dock)

        for tab in SettingsWindow.Tab.allCases {
            f.settings.tabControl.selectedSegment = tab.rawValue
            _ = f.settings.tabControl.target?.perform(
                f.settings.tabControl.action!, with: f.settings.tabControl)
            #expect(f.settings.currentTab == tab, "segment \(tab.rawValue) opened \(f.settings.currentTab)")
        }
        f.close()
    }
}

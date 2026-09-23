import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

/// `HotkeyManager.perform` is the one execution path every input shares; the key
/// handler in front of it is what a keystroke has to get through. Events are built
/// with `NSEvent.keyEvent`, the same shape the monitors deliver.
@Suite("Hotkey manager")
@MainActor
struct HotkeyManagerTests {

    @MainActor
    private struct Fixture {
        let scratch = ScratchPreferences()
        let monitor = MockDisplayMonitor()
        let dock = MockDockController()
        let service: SmartDockService
        let manager: HotkeyManager

        init(externalCount: Int = 1) {
            scratch.prefs.externalConfig = DockConfiguration(autohide: false, position: .bottom)
            scratch.prefs.builtinConfig = DockConfiguration(autohide: true, position: .left)
            monitor.mockExternalCount = externalCount
            service = SmartDockService(displayMonitor: monitor, dockController: dock, prefs: scratch.prefs)
            service.start()
            manager = HotkeyManager(service: service, prefs: scratch.prefs)
        }
    }

    /// ⌃⌥R, keyCode 15 — the shape a recorded binding has.
    private static let controlOptionR = HotkeyBinding(
        keyCode: 15, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, displayName: "R")

    private func keyDown(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: false,
                keyCode: keyCode))
    }

    // MARK: - perform

    @Test func refreshNowReappliesTheCurrentProfile() {
        let f = Fixture()
        let applies = f.dock.applyCallCount

        f.manager.perform(.refreshNow)

        #expect(f.dock.applyCallCount == applies + 1)
    }

    @Test(arguments: [(HotkeyAction.switchToBuiltin, DockProfile.builtin), (.switchToExternal, .external)])
    func switchActionsApplyTheNamedProfile(action: HotkeyAction, profile: DockProfile) {
        let f = Fixture(externalCount: profile == .external ? 0 : 1)  // start on the *other* one

        f.manager.perform(action)

        #expect(f.service.activeProfile == profile)
    }

    /// Writes the toggled value into the profile in force — the regression that
    /// `updateActiveProfile` exists for.
    @Test func toggleAutohideFlipsAndStoresTheProfileInForce() {
        let f = Fixture(externalCount: 1)

        f.manager.perform(.toggleAutohide)

        #expect(f.dock.lastAppliedConfig?.autohide == true)
        #expect(f.scratch.prefs.externalConfig.autohide)
        #expect(
            f.scratch.prefs.builtinConfig.autohide, "the other profile is untouched — it was hidden and stays hidden")
    }

    /// Two presses put things back where they were — even when the Dock refused the
    /// first one, which it does whenever an app is fullscreen. The toggle used to
    /// read the *observed* state, so after a refusal it kept asking for the same
    /// thing and left the stored profile flipped: pressed twice, setting changed.
    @Test func twoTogglesReturnToTheStartEvenWhenTheDockRefuses() {
        let f = Fixture(externalCount: 1)
        f.dock.mockRejectedProperties = [.autohide]
        #expect(!f.scratch.prefs.externalConfig.autohide, "starts visible")

        f.manager.perform(.toggleAutohide)
        #expect(f.scratch.prefs.externalConfig.autohide, "asked to hide")
        #expect(!f.service.currentConfig.autohide, "the Dock refused, and we report what is")

        f.manager.perform(.toggleAutohide)

        #expect(!f.scratch.prefs.externalConfig.autohide, "back where it started")
    }

    @Test func openSettingsTellsTheHost() {
        let f = Fixture()
        var opened = 0
        f.manager.onOpenSettings = { opened += 1 }

        f.manager.perform(.openSettings)

        #expect(opened == 1)
    }

    /// The URL → action mapping is exhaustive at compile time; this pins the pairs.
    @Test(arguments: URLCommand.allCases)
    func everyURLCommandHasAnAction(command: URLCommand) {
        let expected: HotkeyAction =
            switch command {
            case .refresh: .refreshNow
            case .switchToExternal: .switchToExternal
            case .switchToBuiltin: .switchToBuiltin
            case .toggleAutohide: .toggleAutohide
            case .openSettings: .openSettings
            }
        #expect(HotkeyAction(command) == expected)
    }

    // MARK: - Key events

    @Test func aMatchingKeystrokeFiresItsAction() throws {
        let f = Fixture()
        f.scratch.prefs.setHotkey(Self.controlOptionR, for: HotkeyAction.refreshNow.rawValue)
        f.manager.start()
        let applies = f.dock.applyCallCount

        let handled = f.manager.handleKeyEvent(try keyDown(15, [.control, .option]))

        #expect(handled)
        #expect(f.dock.applyCallCount == applies + 1)
        f.manager.stop()
    }

    /// CapsLock rides along on real key events; a binding recorded without it must
    /// still match with it — the reason matching lives in `HotkeyBinding`.
    @Test func capsLockDoesNotBreakAMatch() throws {
        let f = Fixture()
        f.scratch.prefs.setHotkey(Self.controlOptionR, for: HotkeyAction.refreshNow.rawValue)
        f.manager.start()

        #expect(f.manager.handleKeyEvent(try keyDown(15, [.control, .option, .capsLock])))
        f.manager.stop()
    }

    @Test func anUnboundKeystrokeIsIgnored() throws {
        let f = Fixture()
        f.scratch.prefs.setHotkey(Self.controlOptionR, for: HotkeyAction.refreshNow.rawValue)
        f.manager.start()
        let applies = f.dock.applyCallCount

        #expect(!f.manager.handleKeyEvent(try keyDown(15, [.command])))
        #expect(f.dock.applyCallCount == applies)
        f.manager.stop()
    }

    /// Holding the key down must not fire the action dozens of times.
    @Test func aHeldKeyIsRateLimited() throws {
        let f = Fixture()
        f.scratch.prefs.setHotkey(Self.controlOptionR, for: HotkeyAction.refreshNow.rawValue)
        f.manager.start()
        let applies = f.dock.applyCallCount

        let first = f.manager.handleKeyEvent(try keyDown(15, [.control, .option]))
        let second = f.manager.handleKeyEvent(try keyDown(15, [.control, .option]))

        #expect(first && !second)
        #expect(f.dock.applyCallCount == applies + 1)
        f.manager.stop()
    }

    @Test func nothingFiresWhileRecording() throws {
        let f = Fixture()
        f.scratch.prefs.setHotkey(Self.controlOptionR, for: HotkeyAction.refreshNow.rawValue)
        f.manager.start()
        f.manager.isRecording = true

        #expect(!f.manager.handleKeyEvent(try keyDown(15, [.control, .option])))
        f.manager.stop()
    }

    @Test func withNoBindingsNothingIsMonitored() throws {
        let f = Fixture()

        f.manager.start()
        #expect(!f.manager.handleKeyEvent(try keyDown(15, [.control, .option])))

        f.manager.reloadBindings()  // still none: stays stopped
        f.manager.stop()
    }

    @Test func reloadingPicksUpANewBinding() throws {
        let f = Fixture()
        f.manager.start()
        #expect(!f.manager.handleKeyEvent(try keyDown(15, [.control, .option])))

        f.scratch.prefs.setHotkey(Self.controlOptionR, for: HotkeyAction.refreshNow.rawValue)
        f.manager.reloadBindings()

        #expect(f.manager.handleKeyEvent(try keyDown(15, [.control, .option])))
        f.manager.stop()
    }
}

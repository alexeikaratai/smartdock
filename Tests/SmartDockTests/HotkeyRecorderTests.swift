import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

@Suite("Hotkey recorder")
@MainActor
struct HotkeyRecorderTests {

    @MainActor
    private struct Fixture {
        let scratch = ScratchPreferences()
        let service: SmartDockService
        let manager: HotkeyManager
        let recorder: HotkeyRecorder
        let button = NSButton(title: "Click to set", target: nil, action: nil)

        init() {
            service = SmartDockService(
                displayMonitor: MockDisplayMonitor(), dockController: MockDockController(), prefs: scratch.prefs)
            manager = HotkeyManager(service: service, prefs: scratch.prefs)
            recorder = HotkeyRecorder(hotkeyManager: manager, prefs: scratch.prefs)
        }
    }

    private func keyDown(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, _ char: String = "r") throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                context: nil, characters: char, charactersIgnoringModifiers: char, isARepeat: false,
                keyCode: keyCode))
    }

    @Test func recordingPausesDispatchAndNamesTheButton() {
        let f = Fixture()

        f.recorder.start(.refreshNow, in: f.button)

        #expect(f.recorder.isRecording)
        #expect(f.manager.isRecording, "a recorded key must not fire its own action")
        #expect(f.button.title == "Press shortcut...")
        f.recorder.stop()
    }

    @Test func aKeystrokeWithAModifierBecomesTheBinding() throws {
        let f = Fixture()
        var finished = 0
        f.recorder.onFinish = { finished += 1 }
        f.recorder.start(.refreshNow, in: f.button)

        f.recorder.handleRecordedKey(try keyDown(15, [.control, .option]))

        let stored = f.scratch.prefs.hotkey(for: HotkeyAction.refreshNow.rawValue)
        #expect(stored?.keyCode == 15)
        #expect(stored?.displayName == "R")
        #expect(!f.recorder.isRecording && !f.manager.isRecording)
        #expect(finished == 1)
    }

    /// Shift alone would swallow ordinary typing, so it does not count.
    @Test func aKeystrokeWithoutARealModifierIsIgnored() throws {
        let f = Fixture()
        f.recorder.start(.refreshNow, in: f.button)

        f.recorder.handleRecordedKey(try keyDown(15, [.shift]))

        #expect(f.scratch.prefs.hotkey(for: HotkeyAction.refreshNow.rawValue) == nil)
        #expect(f.recorder.isRecording, "still waiting for a real shortcut")
        f.recorder.stop()
    }

    @Test func escapeClearsTheBinding() throws {
        let f = Fixture()
        f.scratch.prefs.setHotkey(
            HotkeyBinding(keyCode: 15, modifiers: NSEvent.ModifierFlags.control.rawValue, displayName: "R"),
            for: HotkeyAction.refreshNow.rawValue)
        f.recorder.start(.refreshNow, in: f.button)

        f.recorder.handleRecordedKey(try keyDown(53, [], "\u{1B}"))

        #expect(f.scratch.prefs.hotkey(for: HotkeyAction.refreshNow.rawValue) == nil)
        #expect(!f.recorder.isRecording)
    }

    @Test func aKeyOutsideARecordingChangesNothing() throws {
        let f = Fixture()

        f.recorder.handleRecordedKey(try keyDown(15, [.control]))

        #expect(f.scratch.prefs.hotkey(for: HotkeyAction.refreshNow.rawValue) == nil)
    }

    @Test func theButtonTitleShowsTheBindingOrAnInvitation() {
        let f = Fixture()
        #expect(HotkeyRecorder.displayTitle(for: .refreshNow, in: f.scratch.prefs) == "Click to set")

        f.scratch.prefs.setHotkey(
            HotkeyBinding(keyCode: 15, modifiers: NSEvent.ModifierFlags.control.rawValue, displayName: "R"),
            for: HotkeyAction.refreshNow.rawValue)

        #expect(HotkeyRecorder.displayTitle(for: .refreshNow, in: f.scratch.prefs).hasSuffix("R"))
    }
}

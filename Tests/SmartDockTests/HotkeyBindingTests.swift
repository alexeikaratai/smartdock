import AppKit
import XCTest

@testable import SmartDockCore

@MainActor
final class HotkeyBindingTests: XCTestCase {

    // MARK: - Helpers

    private func binding(
        keyCode: UInt16 = 4,  // "H"
        modifiers: NSEvent.ModifierFlags,
        displayName: String = "H"
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: keyCode,
            modifiers: HotkeyBinding.normalize(modifiers),
            displayName: displayName
        )
    }

    // MARK: - Normalisation

    func testNormalizeKeepsRelevantModifiers() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        XCTAssertEqual(HotkeyBinding.normalize(flags), flags.rawValue)
    }

    func testNormalizeStripsCapsLock() {
        let normalized = HotkeyBinding.normalize([.command, .capsLock])
        XCTAssertEqual(
            normalized, NSEvent.ModifierFlags.command.rawValue,
            "CapsLock must not survive normalisation")
    }

    func testNormalizeStripsFunctionAndNumericPad() {
        let normalized = HotkeyBinding.normalize([.command, .function, .numericPad])
        XCTAssertEqual(
            normalized, NSEvent.ModifierFlags.command.rawValue,
            "Fn and numeric-pad ride along on ordinary events and must be dropped")
    }

    func testNormalizeOfNoModifiersIsEmpty() {
        XCTAssertEqual(HotkeyBinding.normalize([]), 0)
    }

    // MARK: - Matching

    func testMatchesExactCombination() {
        let hotkey = binding(modifiers: [.command, .shift])
        XCTAssertTrue(hotkey.matches(keyCode: 4, modifiers: [.command, .shift]))
    }

    func testDoesNotMatchDifferentKeyCode() {
        let hotkey = binding(modifiers: [.command])
        XCTAssertFalse(hotkey.matches(keyCode: 5, modifiers: [.command]))
    }

    func testDoesNotMatchDifferentModifiers() {
        let hotkey = binding(modifiers: [.command])
        XCTAssertFalse(hotkey.matches(keyCode: 4, modifiers: [.control]))
    }

    func testDoesNotMatchWhenExtraRelevantModifierPressed() {
        let hotkey = binding(modifiers: [.command])
        XCTAssertFalse(
            hotkey.matches(keyCode: 4, modifiers: [.command, .shift]),
            "⌘H must not fire on ⇧⌘H")
    }

    /// Regression guard: a hotkey recorded without CapsLock previously stopped
    /// matching once CapsLock was engaged, because the raw flags were compared.
    func testMatchesWhileCapsLockIsOn() {
        let hotkey = binding(modifiers: [.command, .option])
        XCTAssertTrue(hotkey.matches(keyCode: 4, modifiers: [.command, .option, .capsLock]))
    }

    func testMatchesWhileFunctionKeyFlagIsSet() {
        let hotkey = binding(modifiers: [.control])
        XCTAssertTrue(hotkey.matches(keyCode: 4, modifiers: [.control, .function]))
    }

    /// The contract that keeps `HotkeyRecorder` and `HotkeyManager` in step:
    /// whatever flags recording stores must match the very event that produced them.
    func testRecordedBindingMatchesTheEventItWasRecordedFrom() {
        let rawFlags: NSEvent.ModifierFlags = [.command, .shift, .capsLock, .function]
        let recorded = binding(modifiers: rawFlags)
        XCTAssertTrue(recorded.matches(keyCode: 4, modifiers: rawFlags))
    }

    // MARK: - Required Modifier

    func testShiftAloneIsNotEnoughToBind() {
        XCTAssertFalse(
            HotkeyBinding.hasRequiredModifier([.shift]),
            "⇧+letter would swallow ordinary typing")
    }

    func testNoModifierIsNotEnoughToBind() {
        XCTAssertFalse(HotkeyBinding.hasRequiredModifier([]))
    }

    func testCapsLockAloneIsNotEnoughToBind() {
        XCTAssertFalse(HotkeyBinding.hasRequiredModifier([.capsLock]))
    }

    func testCommandOptionOrControlIsEnoughToBind() {
        XCTAssertTrue(HotkeyBinding.hasRequiredModifier([.command]))
        XCTAssertTrue(HotkeyBinding.hasRequiredModifier([.option]))
        XCTAssertTrue(HotkeyBinding.hasRequiredModifier([.control]))
        XCTAssertTrue(HotkeyBinding.hasRequiredModifier([.shift, .command]))
    }

    // MARK: - Display

    func testDisplayStringUsesStandardModifierOrder() {
        let hotkey = binding(modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(hotkey.displayString, "⌃⌥⇧⌘H")
    }

    func testDisplayStringWithSingleModifier() {
        XCTAssertEqual(binding(modifiers: [.command]).displayString, "⌘H")
        XCTAssertEqual(binding(modifiers: [.control]).displayString, "⌃H")
    }

    func testDisplayStringOmitsStrippedModifiers() {
        let hotkey = binding(modifiers: [.command, .capsLock, .function])
        XCTAssertEqual(hotkey.displayString, "⌘H")
    }

    func testDisplayStringUsesRecordedKeyName() {
        let hotkey = binding(modifiers: [.command], displayName: "R")
        XCTAssertEqual(hotkey.displayString, "⌘R")
    }

    // MARK: - Persistence Round-Trip

    func testHotkeySurvivesSaveAndLoad() {
        let prefs = UserPreferences.shared
        let original = binding(modifiers: [.command, .option], displayName: "K")

        prefs.setHotkey(original, for: "testAction")
        defer { prefs.setHotkey(nil, for: "testAction") }

        XCTAssertEqual(prefs.hotkey(for: "testAction"), original)
    }

    func testClearingHotkeyRemovesIt() {
        let prefs = UserPreferences.shared
        prefs.setHotkey(binding(modifiers: [.command]), for: "testAction")
        prefs.setHotkey(nil, for: "testAction")

        XCTAssertNil(prefs.hotkey(for: "testAction"))
    }
}

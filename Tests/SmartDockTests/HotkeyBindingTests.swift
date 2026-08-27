import AppKit
import Testing

@testable import SmartDockCore

@Suite("Hotkey bindings")
@MainActor
struct HotkeyBindingTests {

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

    @Test func normalizeKeepsRelevantModifiers() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

        #expect(HotkeyBinding.normalize(flags) == flags.rawValue)
    }

    @Test func normalizeStripsCapsLock() {
        #expect(
            HotkeyBinding.normalize([.command, .capsLock]) == NSEvent.ModifierFlags.command.rawValue,
            "CapsLock must not survive normalisation")
    }

    @Test func normalizeStripsFunctionAndNumericPad() {
        #expect(
            HotkeyBinding.normalize([.command, .function, .numericPad])
                == NSEvent.ModifierFlags.command.rawValue,
            "Fn and numeric-pad ride along on ordinary events and must be dropped")
    }

    @Test func normalizeOfNoModifiersIsEmpty() {
        #expect(HotkeyBinding.normalize([]) == 0)
    }

    // MARK: - Matching

    @Test func matchesExactCombination() {
        let hotkey = binding(modifiers: [.command, .shift])

        #expect(hotkey.matches(keyCode: 4, modifiers: [.command, .shift]))
    }

    @Test func doesNotMatchDifferentKeyCode() {
        let hotkey = binding(modifiers: [.command])

        #expect(!hotkey.matches(keyCode: 5, modifiers: [.command]))
    }

    @Test func doesNotMatchDifferentModifiers() {
        let hotkey = binding(modifiers: [.command])

        #expect(!hotkey.matches(keyCode: 4, modifiers: [.control]))
    }

    @Test func doesNotMatchWhenExtraRelevantModifierPressed() {
        let hotkey = binding(modifiers: [.command])

        #expect(!hotkey.matches(keyCode: 4, modifiers: [.command, .shift]), "⌘H must not fire on ⇧⌘H")
    }

    /// Regression guard: a hotkey recorded without CapsLock previously stopped
    /// matching once CapsLock was engaged, because the raw flags were compared.
    @Test func matchesWhileCapsLockIsOn() {
        let hotkey = binding(modifiers: [.command, .option])

        #expect(hotkey.matches(keyCode: 4, modifiers: [.command, .option, .capsLock]))
    }

    @Test func matchesWhileFunctionKeyFlagIsSet() {
        let hotkey = binding(modifiers: [.control])

        #expect(hotkey.matches(keyCode: 4, modifiers: [.control, .function]))
    }

    /// The contract that keeps `HotkeyRecorder` and `HotkeyManager` in step:
    /// whatever flags recording stores must match the very event that produced them.
    @Test func recordedBindingMatchesTheEventItWasRecordedFrom() {
        let rawFlags: NSEvent.ModifierFlags = [.command, .shift, .capsLock, .function]
        let recorded = binding(modifiers: rawFlags)

        #expect(recorded.matches(keyCode: 4, modifiers: rawFlags))
    }

    // MARK: - Required Modifier

    @Test func shiftAloneIsNotEnoughToBind() {
        #expect(
            !HotkeyBinding.hasRequiredModifier([.shift]),
            "⇧+letter would swallow ordinary typing")
    }

    @Test(arguments: [NSEvent.ModifierFlags([]), [.capsLock]])
    func weakModifiersAreNotEnoughToBind(flags: NSEvent.ModifierFlags) {
        #expect(!HotkeyBinding.hasRequiredModifier(flags))
    }

    @Test(arguments: [
        NSEvent.ModifierFlags.command, .option, .control, [.shift, .command],
    ])
    func commandOptionOrControlIsEnoughToBind(flags: NSEvent.ModifierFlags) {
        #expect(HotkeyBinding.hasRequiredModifier(flags))
    }

    // MARK: - Display

    @Test func displayStringUsesStandardModifierOrder() {
        let hotkey = binding(modifiers: [.command, .shift, .option, .control])

        #expect(hotkey.displayString == "⌃⌥⇧⌘H")
    }

    @Test func displayStringWithSingleModifier() {
        #expect(binding(modifiers: [.command]).displayString == "⌘H")
        #expect(binding(modifiers: [.control]).displayString == "⌃H")
    }

    @Test func displayStringOmitsStrippedModifiers() {
        let hotkey = binding(modifiers: [.command, .capsLock, .function])

        #expect(hotkey.displayString == "⌘H")
    }

    @Test func displayStringUsesRecordedKeyName() {
        #expect(binding(modifiers: [.command], displayName: "R").displayString == "⌘R")
    }

    // MARK: - Persistence Round-Trip

    @Test func hotkeySurvivesSaveAndLoad() {
        let scratch = ScratchPreferences()
        let original = binding(modifiers: [.command, .option], displayName: "K")

        scratch.prefs.setHotkey(original, for: "testAction")

        #expect(scratch.prefs.hotkey(for: "testAction") == original)
    }

    @Test func clearingHotkeyRemovesIt() {
        let scratch = ScratchPreferences()
        scratch.prefs.setHotkey(binding(modifiers: [.command]), for: "testAction")

        scratch.prefs.setHotkey(nil, for: "testAction")

        #expect(scratch.prefs.hotkey(for: "testAction") == nil)
    }
}

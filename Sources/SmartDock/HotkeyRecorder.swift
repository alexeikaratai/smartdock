import Cocoa
import SmartDockCore

// MARK: - Hotkey Recorder

/// Captures a keystroke and stores it as the binding for a `HotkeyAction`.
///
/// While recording, `HotkeyManager` is paused so the keystroke being recorded
/// doesn't also fire the action it is being bound to.
@MainActor
final class HotkeyRecorder {

    /// Fired after a binding is stored or cleared — the host refreshes its buttons.
    var onFinish: (() -> Void)?

    /// Whether a keystroke is currently being captured.
    var isRecording: Bool { action != nil }

    private let hotkeyManager: HotkeyManager
    private let prefs = UserPreferences.shared

    private var monitor: Any?
    private var action: HotkeyAction?

    /// Virtual key code for Escape — clears the binding.
    private static let escapeKeyCode: UInt16 = 53

    // MARK: - Init

    init(hotkeyManager: HotkeyManager) {
        self.hotkeyManager = hotkeyManager
    }

    // MARK: - Public

    /// Title to show on the button for the given action.
    static func displayTitle(for action: HotkeyAction) -> String {
        guard let binding = UserPreferences.shared.hotkey(for: action.rawValue) else {
            return "Click to set"
        }
        return binding.displayString
    }

    func start(_ action: HotkeyAction, in button: NSButton) {
        self.action = action
        hotkeyManager.isRecording = true
        button.title = "Press shortcut..."

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handleRecordedKey(event)
            return nil  // consumed — never let a recorded key reach the app
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        action = nil
        hotkeyManager.isRecording = false
        hotkeyManager.reloadBindings()
        onFinish?()
    }

    // MARK: - Private

    private func handleRecordedKey(_ event: NSEvent) {
        guard let action else { return }

        if event.keyCode == Self.escapeKeyCode {
            prefs.setHotkey(nil, for: action.rawValue)
            stop()
            return
        }

        // Require a non-shift modifier — a bare letter would swallow normal typing.
        guard HotkeyBinding.hasRequiredModifier(event.modifierFlags) else { return }

        let binding = HotkeyBinding(
            keyCode: event.keyCode,
            modifiers: HotkeyBinding.normalize(event.modifierFlags),
            displayName: event.charactersIgnoringModifiers?.uppercased() ?? "?"
        )
        prefs.setHotkey(binding, for: action.rawValue)
        stop()
    }
}

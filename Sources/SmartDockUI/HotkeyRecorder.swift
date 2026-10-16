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

    /// Which action is being recorded, so the row for it can say so. It used to be told
    /// by having its `NSButton` handed in and its title overwritten; a SwiftUI row has no
    /// button to hand over, and a recorder that reaches into a control was the reason the
    /// two had to be built together at all.
    private(set) var recordingAction: HotkeyAction?

    private let hotkeyManager: HotkeyManager
    private let prefs: UserPreferences
    /// Installing and removing the key monitor leaves the process, so both are
    /// parameters — the rule every other outward call here already follows. Until they
    /// were, a monitor left behind by a second `start` without a `stop` was invisible:
    /// the titles looked right while two monitors each swallowed the same keystroke.
    private let installMonitor: @MainActor (HotkeyRecorder) -> Any?
    private let removeMonitor: @MainActor (Any) -> Void

    private var monitor: Any?
    private var action: HotkeyAction?

    /// Virtual key code for Escape — clears the binding.
    private static let escapeKeyCode: UInt16 = 53

    // MARK: - Init

    init(
        hotkeyManager: HotkeyManager,
        prefs: UserPreferences = .shared,
        // Takes the recorder rather than a handler closure: `NSEvent` is not
        // `Sendable`, so a closure carrying one across the seam does not compile, while
        // the monitor calling a method on the recorder does — which is what the inline
        // version always did.
        installMonitor: @escaping @MainActor (HotkeyRecorder) -> Any? = { recorder in
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak recorder] event in
                guard let recorder else { return event }
                recorder.handleRecordedKey(event)
                return nil  // consumed — never let a recorded key reach the app
            }
        },
        removeMonitor: @escaping @MainActor (Any) -> Void = { NSEvent.removeMonitor($0) }
    ) {
        self.prefs = prefs
        self.hotkeyManager = hotkeyManager
        self.installMonitor = installMonitor
        self.removeMonitor = removeMonitor
    }

    // MARK: - Public

    /// Title to show on the button for the given action.
    static func displayTitle(for action: HotkeyAction, in prefs: UserPreferences) -> String {
        guard let binding = prefs.hotkey(for: action.rawValue) else {
            return "Click to set"
        }
        return binding.displayString
    }

    /// Stops whatever was listening first. Two monitors at once each consume the same
    /// keystroke, and the one left behind outlives the row that asked for it.
    func start(_ action: HotkeyAction) {
        if isRecording { stop() }
        self.action = action
        recordingAction = action
        hotkeyManager.isRecording = true

        monitor = installMonitor(self)
    }

    func stop() {
        if let monitor {
            removeMonitor(monitor)
            self.monitor = nil
        }
        action = nil
        recordingAction = nil
        hotkeyManager.isRecording = false
        hotkeyManager.reloadBindings()
        onFinish?()
    }

    // MARK: - Private

    /// Internal rather than private so a test can feed it a synthetic `NSEvent` the
    /// way the local monitor would.
    func handleRecordedKey(_ event: NSEvent) {
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

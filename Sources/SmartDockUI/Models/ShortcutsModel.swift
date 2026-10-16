import Observation
import SmartDockCore

// MARK: - Shortcuts Model

/// The Shortcuts tab: the permission global hotkeys need, and the five bindings
/// themselves.
///
/// Recording is a state here rather than a title written into a button. The recorder used
/// to be handed the `NSButton` it should overwrite, which tied it to the control it was
/// decorating; now it says **which action** is being recorded and the row for that action
/// says so itself.
@MainActor
@Observable
final class ShortcutsModel {

    let accessibility: AccessibilityStatusModel

    /// Which action is listening for a keystroke, if any.
    private(set) var recordingAction: HotkeyAction?
    /// Bumped whenever a binding is stored or cleared, so the rows re-read their titles.
    /// The bindings live in `UserPreferences`, which is not observable.
    private(set) var revision = 0

    @ObservationIgnored private let prefs: UserPreferences
    @ObservationIgnored private let recorder: HotkeyRecorder

    // MARK: - Init

    init(
        recorder: HotkeyRecorder,
        accessibility: AccessibilityStatusModel,
        prefs: UserPreferences = .shared
    ) {
        self.recorder = recorder
        self.accessibility = accessibility
        self.prefs = prefs
    }

    // MARK: - Reading

    /// What the row for an action shows: the keystroke, an invitation, or — while it is
    /// listening — what it is waiting for.
    func title(for action: HotkeyAction) -> String {
        _ = revision
        if recordingAction == action { return "Press shortcut\u{2026}" }
        return HotkeyRecorder.displayTitle(for: action, in: prefs)
    }

    // MARK: - Intents

    /// Starts listening, stopping whatever was listening before: two recorders at once
    /// would each consume the same keystroke.
    func record(_ action: HotkeyAction) {
        if recorder.isRecording { recorder.stop() }
        recorder.start(action)
        recordingAction = action
    }

    /// Leaving the tab, closing the window or pressing Escape ends a recording — a
    /// monitor that outlives the tab swallows keystrokes meant for the app.
    func stopRecording() {
        guard recorder.isRecording else { return }
        recorder.stop()
        recordingAction = nil
    }

    /// Called by the host when the recorder finishes on its own, having stored or cleared
    /// a binding.
    func recordingFinished() {
        recordingAction = nil
        revision += 1
    }
}

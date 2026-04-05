import Cocoa
import SmartDockCore

// MARK: - Hotkey Action

enum HotkeyAction: String, CaseIterable, Sendable {
    case toggleAutohide
    case refreshNow

    var displayName: String {
        switch self {
        case .toggleAutohide: return "Toggle Autohide"
        case .refreshNow:     return "Refresh Now"
        }
    }
}

// MARK: - Hotkey Manager

/// Registers global keyboard shortcuts and dispatches actions.
/// Uses `NSEvent.addGlobalMonitorForEvents` (background) and
/// `addLocalMonitorForEvents` (foreground) to catch hotkeys in all states.
@MainActor
final class HotkeyManager {

    private let service: SmartDockService
    private let prefs = UserPreferences.shared

    /// Accessed from deinit (nonisolated) and @MainActor methods.
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var localMonitor: Any?

    /// When true, monitors skip dispatch — used during hotkey recording in Settings.
    var isRecording = false

    // MARK: - Init

    init(service: SmartDockService) {
        self.service = service
    }

    deinit {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Public

    func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            self.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleKeyEvent(event) {
                return nil // consumed
            }
            return event
        }

        Log.info("Hotkey monitoring started")
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // MARK: - Private

    /// Returns true if the event matched a hotkey binding.
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !isRecording else { return false }

        // Strip CapsLock and Function flags — only match Cmd/Ctrl/Opt/Shift.
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
        let keyCode = event.keyCode

        for action in HotkeyAction.allCases {
            guard let binding = prefs.hotkey(for: action.rawValue) else { continue }
            if binding.keyCode == keyCode && binding.modifiers == modifiers {
                executeAction(action)
                return true
            }
        }

        return false
    }

    private func executeAction(_ action: HotkeyAction) {
        switch action {
        case .toggleAutohide:
            toggleAutohide()
        case .refreshNow:
            service.refresh()
            Log.info("Hotkey: refreshed dock config")
        }
    }

    private func toggleAutohide() {
        let current = service.currentConfig

        let toggled = DockConfiguration(
            autohide: !current.autohide,
            position: current.position,
            iconSize: current.iconSize,
            magnification: current.magnification,
            magnificationSize: current.magnificationSize
        )

        if service.hasExternalDisplay {
            prefs.externalConfig = toggled
        } else {
            prefs.builtinConfig = toggled
        }

        service.refresh()
        Log.info("Hotkey: toggled autohide → \(!current.autohide)")
    }
}

// MARK: - Hotkey Display Helpers

extension HotkeyManager {

    /// Format a hotkey binding for display, e.g. "⌃⌥H".
    static func displayString(for binding: HotkeyBinding) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(binding.modifiers))
        var parts: [String] = []

        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        parts.append(binding.displayName)
        return parts.joined()
    }
}

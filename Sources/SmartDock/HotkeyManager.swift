import Cocoa
import SmartDockCore

// MARK: - Hotkey Action

enum HotkeyAction: String, CaseIterable, Sendable {
    case toggleAutohide
    case refreshNow
    case switchToExternal
    case switchToBuiltin
    case openSettings

    var displayName: String {
        switch self {
        case .toggleAutohide: return "Toggle Autohide"
        case .refreshNow: return "Refresh Now"
        case .switchToExternal: return "Apply External Profile"
        case .switchToBuiltin: return "Apply Built-in Profile"
        case .openSettings: return "Open Settings"
        }
    }

    /// The action a `smartdock://` URL maps to, so URLs and hotkeys run through
    /// one execution path. Exhaustive on purpose — adding a case to either enum
    /// breaks the build until the mapping is updated.
    init(_ command: URLCommand) {
        switch command {
        case .refresh: self = .refreshNow
        case .switchToExternal: self = .switchToExternal
        case .switchToBuiltin: self = .switchToBuiltin
        case .toggleAutohide: self = .toggleAutohide
        case .openSettings: self = .openSettings
        }
    }
}

// MARK: - Hotkey Manager

/// Registers global keyboard shortcuts and dispatches actions.
/// Uses `NSEvent.addGlobalMonitorForEvents` (background) and
/// `addLocalMonitorForEvents` (foreground) to catch hotkeys in all states.
@MainActor
final class HotkeyManager: NSObject {

    private let service: SmartDockService
    private let prefs = UserPreferences.shared

    /// Called when Open Settings hotkey is pressed.
    var onOpenSettings: (() -> Void)?

    /// Accessed from deinit (nonisolated) and @MainActor methods.
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var localMonitor: Any?

    /// Cached hotkey bindings — avoids UserDefaults reads on every keystroke.
    private var cachedBindings: [(action: HotkeyAction, binding: HotkeyBinding)] = []

    /// When true, monitors skip dispatch — used during hotkey recording in Settings.
    var isRecording = false

    // MARK: - Init

    init(service: SmartDockService) {
        self.service = service
        super.init()

        // Re-create monitors when SmartDock becomes active —
        // picks up any Accessibility permission changes made in System Settings.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
    }

    @objc private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        else { return }
        // Restart monitors so they re-check Accessibility status
        if !cachedBindings.isEmpty {
            start()
        }
    }

    // MARK: - Public

    func start() {
        stop()
        refreshBindingCache()

        // Only install monitors if at least one hotkey is configured.
        guard !cachedBindings.isEmpty else {
            Log.info("Hotkey monitoring skipped — no hotkeys configured")
            return
        }

        let isTrusted = AXIsProcessTrusted()
        Log.info("Hotkey start: AXIsProcessTrusted=\(isTrusted), bindings=\(cachedBindings.count)")

        // Never log event details here — this closure runs for every keystroke
        // system-wide, and keyCodes in the unified log would expose typed text.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            self.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleKeyEvent(event) {
                return nil  // consumed
            }
            return event
        }

        if globalMonitor == nil {
            Log.error("Global monitor failed to register (Accessibility permission likely missing)")
        }

        Log.info("Hotkey monitoring started (\(cachedBindings.count) binding(s))")
    }

    /// Reload cached bindings from UserPreferences and restart monitors.
    /// Always restarts to pick up any Accessibility permission changes —
    /// `addGlobalMonitorForEvents` doesn't react to permission grants
    /// after the monitor was created.
    func reloadBindings() {
        refreshBindingCache()

        if cachedBindings.isEmpty {
            stop()
        } else {
            start()
        }
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

    /// Minimum interval between hotkey executions, so holding a shortcut down does
    /// not fire it dozens of times. Consulted only once a binding has matched —
    /// an unrelated keystroke must not consume the allowance.
    private var rateLimiter = RateLimiter(interval: 0.3)

    /// Returns true if the event matched a hotkey binding.
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !isRecording, !cachedBindings.isEmpty else { return false }

        for (action, binding) in cachedBindings
        where binding.matches(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            guard rateLimiter.allow(at: Date()) else { return false }
            perform(action)
            return true
        }

        return false
    }

    private func refreshBindingCache() {
        cachedBindings = HotkeyAction.allCases.compactMap { action in
            guard let binding = prefs.hotkey(for: action.rawValue) else { return nil }
            return (action, binding)
        }
    }

    /// Runs an action. Shared by the hotkey monitors and the `smartdock://` URL scheme.
    func perform(_ action: HotkeyAction) {
        switch action {
        case .toggleAutohide:
            toggleAutohide()
        case .refreshNow:
            service.refresh()
            Log.info("Hotkey: refreshed dock config")
        case .switchToExternal:
            applyProfile(external: true)
        case .switchToBuiltin:
            applyProfile(external: false)
        case .openSettings:
            onOpenSettings?()
            Log.info("Hotkey: opened settings")
        }
    }

    private func applyProfile(external: Bool) {
        service.applyProfile(external: external)
    }

    private func toggleAutohide() {
        let current = service.currentConfig

        // `with` rather than rebuilding field by field: this call site used to list
        // every property, so each new setting silently reverted to its default the
        // moment somebody toggled auto-hide.
        let toggled = current.with(autohide: !current.autohide)

        if service.hasExternalDisplay {
            prefs.externalConfig = toggled
        } else {
            prefs.builtinConfig = toggled
        }

        service.refresh()
        Log.info("Hotkey: toggled autohide → \(!current.autohide)")
    }
}

import Foundation

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when the service applies a new dock configuration.
    /// `userInfo` contains `SmartDockService.hasExternalKey` (Bool).
    static let smartDockStateDidChange = Notification.Name("com.smartdock.stateDidChange")
}

public extension SmartDockService {
    static let hasExternalKey = "hasExternal"
}

// MARK: - Delegate

/// Delegate for receiving state change notifications.
@MainActor
public protocol SmartDockServiceDelegate: AnyObject {
    func serviceDidUpdateState(_ service: SmartDockService, hasExternal: Bool)
}

// MARK: - Service

/// Main application service.
/// Links DisplayMonitor and DockController:
/// applies the appropriate DockConfiguration based on whether
/// an external monitor is connected or not.
@MainActor
public final class SmartDockService {

    public weak var delegate: (any SmartDockServiceDelegate)?

    /// Whether the service is active
    public private(set) var isEnabled: Bool = false

    /// Last known state (whether there is an external monitor)
    public private(set) var hasExternalDisplay: Bool = false

    /// Number of active external displays, read live. Used by diagnostics —
    /// `hasExternalDisplay` is the cached state the profile decision was made on.
    public var externalDisplayCount: Int { displayMonitor.externalDisplayCount() }

    /// The dock configuration we last applied (not the transient system state).
    public private(set) var currentConfig: DockConfiguration = DockConfiguration()

    private let displayMonitor: any DisplayMonitoring
    public let dockController: any DockControlling
    private let prefs: UserPreferences

    // MARK: - Init

    public init(
        displayMonitor: any DisplayMonitoring = DisplayMonitor(),
        dockController: any DockControlling = DockController(),
        prefs: UserPreferences = .shared
    ) {
        self.displayMonitor = displayMonitor
        self.dockController = dockController
        self.prefs = prefs

        self.displayMonitor.onConfigurationChanged = { [weak self] in
            self?.handleDisplayChange()
        }

        self.dockController.onExternalConfigChanged = { [weak self] config in
            self?.handleExternalDockChange(config)
        }

        self.dockController.onApplyVerified = { [weak self] outcome, actual in
            self?.handleApplyVerified(outcome, actual: actual)
        }
    }

    // MARK: - Public

    public func start() {
        guard !isEnabled else { return }
        isEnabled = true

        prefs.initializeDefaultsIfNeeded(from: dockController.readSystemConfig())

        displayMonitor.start()
        dockController.startObservingSystemChanges()
        applyCurrentState()
        Log.info("SmartDock service started")
    }

    public func stop() {
        guard isEnabled else { return }
        isEnabled = false
        displayMonitor.stop()
        dockController.stopObservingSystemChanges()
        Log.info("SmartDock service stopped")
    }

    /// Recalculate and apply state.
    public func refresh() {
        applyCurrentState()
    }

    /// Apply a profile the user asked for by name, overriding the one the current
    /// display setup would select.
    ///
    /// Deliberately **not** implemented as "apply, then `refresh()`": `refresh()`
    /// re-derives the profile from the displays, so it would undo the request
    /// within the same call — and the only time forcing a profile is useful is
    /// precisely when it disagrees with the displays.
    ///
    /// The override holds until the next display change, wake or refresh, at which
    /// point automatic behaviour resumes.
    public func applyProfile(external: Bool) {
        guard isEnabled, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        let config = external ? prefs.externalConfig : prefs.builtinConfig
        let changed = config != currentConfig

        currentConfig = config
        dockController.apply(config)
        Log.info("Applied \(external ? "external" : "built-in") profile on request")

        // `hasExternalDisplay` keeps reporting the hardware, which has not changed —
        // only the profile in force has.
        if changed { notifyStateChanged() }
    }

    // MARK: - Private

    /// Brings the reported state back in line when the Dock did not honour an apply.
    ///
    /// `currentConfig` is recorded optimistically — deliberately so, because the Dock
    /// passes through transient states and reading it back immediately would report
    /// noise. A *refused* setting is not transient, though: left alone, the menu bar
    /// goes on showing a hidden Dock while the Dock sits there in plain view.
    /// Verification runs once that transient window has passed, which makes it the
    /// right moment to reconcile.
    ///
    /// The stored profile is deliberately **not** touched. The user still wants
    /// auto-hide; macOS just would not do it right now. Rewriting the preference
    /// would throw their choice away over a temporary refusal — and it would come
    /// back the next time the profile is applied under conditions that allow it.
    private func handleApplyVerified(_ outcome: DockApplyOutcome, actual: DockConfiguration) {
        guard !outcome.isComplete else { return }

        Log.info("Reporting what the Dock actually holds — \(outcome.summary)")
        currentConfig = actual
        notifyStateChanged()
    }

    private var isApplying = false

    private func handleDisplayChange() {
        guard isEnabled else { return }
        applyCurrentState()
    }

    /// System dock settings changed externally (e.g. via System Settings).
    /// Update the currently active profile to match.
    private func handleExternalDockChange(_ config: DockConfiguration) {
        guard isEnabled, !isApplying else { return }
        guard prefs.syncFromSystemEnabled else { return }

        if hasExternalDisplay {
            prefs.externalConfig = config
            Log.info("External dock change detected — updated external profile")
        } else {
            prefs.builtinConfig = config
            Log.info("External dock change detected — updated built-in profile")
        }

        currentConfig = config
        notifyStateChanged()
    }

    private func applyCurrentState() {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        let previousConfig = currentConfig
        let previousExternal = hasExternalDisplay

        let external = displayMonitor.hasExternalDisplay()
        hasExternalDisplay = external

        let config: DockConfiguration
        if external {
            config = prefs.externalConfig
            Log.displayChange("External display detected — applying external config")
        } else {
            config = prefs.builtinConfig
            Log.displayChange("No external displays — applying built-in config")
        }

        currentConfig = config
        dockController.apply(config)

        // Only notify observers when state actually changed.
        if config != previousConfig || external != previousExternal {
            notifyStateChanged()
        }
    }

    private func notifyStateChanged() {
        delegate?.serviceDidUpdateState(self, hasExternal: hasExternalDisplay)
        NotificationCenter.default.post(
            name: .smartDockStateDidChange,
            object: self,
            userInfo: [SmartDockService.hasExternalKey: hasExternalDisplay]
        )
    }
}

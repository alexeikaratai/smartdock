import Foundation

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

    public weak var delegate: SmartDockServiceDelegate?

    /// Whether the service is active
    public private(set) var isEnabled: Bool = false

    /// Last known state (whether there is an external monitor)
    public private(set) var hasExternalDisplay: Bool = false

    private let displayMonitor: DisplayMonitoring
    public let dockController: DockControlling
    private let prefs: UserPreferences

    // MARK: - Init

    /// - Parameters:
    ///   - displayMonitor: Display monitoring object (injectable for tests)
    ///   - dockController: Dock management object (injectable for tests)
    ///   - prefs: User preferences for dock configuration per mode
    public init(
        displayMonitor: DisplayMonitoring = DisplayMonitor(),
        dockController: DockControlling = DockController(),
        prefs: UserPreferences = .shared
    ) {
        self.displayMonitor = displayMonitor
        self.dockController = dockController
        self.prefs = prefs

        self.displayMonitor.onConfigurationChanged = { [weak self] in
            self?.handleDisplayChange()
        }
    }

    // MARK: - Public

    /// Enable the service: start monitoring and apply current state
    public func start() {
        guard !isEnabled else { return }
        isEnabled = true
        displayMonitor.start()
        applyCurrentState()
        Log.info("SmartDock service started")
    }

    /// Disable the service: stop monitoring
    public func stop() {
        guard isEnabled else { return }
        isEnabled = false
        displayMonitor.stop()
        Log.info("SmartDock service stopped")
    }

    /// Recalculate and apply state (called from Settings when user changes a preference)
    public func refresh() {
        applyCurrentState()
    }

    // MARK: - Private

    private func handleDisplayChange() {
        guard isEnabled else { return }
        applyCurrentState()
    }

    private func applyCurrentState() {
        let external = displayMonitor.hasExternalDisplay()
        let externalCount = displayMonitor.externalDisplayCount()
        hasExternalDisplay = external

        let config: DockConfiguration
        if external {
            config = prefs.externalConfig
            Log.displayChange("External display connected (\(externalCount) external) — applying external config")
        } else {
            config = prefs.builtinConfig
            Log.displayChange("No external displays — applying built-in config")
        }

        dockController.apply(config)
        delegate?.serviceDidUpdateState(self, hasExternal: external)
    }
}

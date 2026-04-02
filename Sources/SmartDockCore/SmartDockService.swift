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

    public weak var delegate: SmartDockServiceDelegate?

    /// Whether the service is active
    public private(set) var isEnabled: Bool = false

    /// Last known state (whether there is an external monitor)
    public private(set) var hasExternalDisplay: Bool = false

    /// The dock configuration we last applied (not the transient system state).
    public private(set) var currentConfig: DockConfiguration = DockConfiguration()

    private let displayMonitor: DisplayMonitoring
    public let dockController: DockControlling
    private let prefs: UserPreferences

    // MARK: - Init

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

    public func start() {
        guard !isEnabled else { return }
        isEnabled = true

        prefs.initializeDefaultsIfNeeded(from: dockController.readSystemConfig())

        displayMonitor.start()
        applyCurrentState()
        Log.info("SmartDock service started")
    }

    public func stop() {
        guard isEnabled else { return }
        isEnabled = false
        displayMonitor.stop()
        Log.info("SmartDock service stopped")
    }

    /// Recalculate and apply state.
    public func refresh() {
        applyCurrentState()
    }

    // MARK: - Private

    private var isApplying = false

    private func handleDisplayChange() {
        guard isEnabled else { return }
        applyCurrentState()
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
            delegate?.serviceDidUpdateState(self, hasExternal: external)

            NotificationCenter.default.post(
                name: .smartDockStateDidChange,
                object: self,
                userInfo: [SmartDockService.hasExternalKey: external]
            )
        }
    }
}

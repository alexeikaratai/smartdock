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
/// shows the Dock when an external monitor appears,
/// hides it when disconnected.
@MainActor
public final class SmartDockService {

    public weak var delegate: SmartDockServiceDelegate?

    /// Whether the service is active
    public private(set) var isEnabled: Bool = false

    /// Last known state (whether there is an external monitor)
    public private(set) var hasExternalDisplay: Bool = false

    private let displayMonitor: DisplayMonitoring
    private let dockController: DockControlling

    // MARK: - Init

    /// - Parameters:
    ///   - displayMonitor: Display monitoring object (injectable for tests)
    ///   - dockController: Dock management object (injectable for tests)
    public init(
        displayMonitor: DisplayMonitoring = DisplayMonitor(),
        dockController: DockControlling = DockController()
    ) {
        self.displayMonitor = displayMonitor
        self.dockController = dockController

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

    /// Forcefully recalculate and apply state
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

        if external {
            Log.displayChange("External display connected (\(externalCount) external)")
            dockController.setAutoHide(false)
        } else {
            Log.displayChange("No external displays — built-in only")
            dockController.setAutoHide(true)
        }

        delegate?.serviceDidUpdateState(self, hasExternal: external)
    }
}

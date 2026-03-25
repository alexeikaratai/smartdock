import Foundation
@testable import SmartDockCore

// MARK: - Mock Display Monitor

@MainActor
final class MockDisplayMonitor: DisplayMonitoring {
    var onConfigurationChanged: (() -> Void)?

    var mockExternalCount: Int = 0
    var startCallCount = 0
    var stopCallCount = 0

    func externalDisplayCount() -> Int {
        mockExternalCount
    }

    func hasExternalDisplay() -> Bool {
        mockExternalCount > 0
    }

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    /// Simulates monitor connection/disconnection
    func simulateDisplayChange(externalCount: Int) {
        mockExternalCount = externalCount
        onConfigurationChanged?()
    }
}

// MARK: - Mock Dock Controller

final class MockDockController: DockControlling {
    var autoHideState: Bool = false
    var setAutoHideCallCount = 0
    var lastAutoHideValue: Bool?
    var applyCallCount = 0
    var lastAppliedConfig: DockConfiguration?
    var mockSystemConfig = DockConfiguration()

    func isAutoHideEnabled() -> Bool {
        autoHideState
    }

    @discardableResult
    func setAutoHide(_ enabled: Bool) -> Bool {
        setAutoHideCallCount += 1
        lastAutoHideValue = enabled
        autoHideState = enabled
        return true
    }

    @discardableResult
    func apply(_ config: DockConfiguration) -> Bool {
        applyCallCount += 1
        lastAppliedConfig = config
        autoHideState = config.autohide
        return true
    }

    func readSystemConfig() -> DockConfiguration {
        mockSystemConfig
    }
}

// MARK: - Mock Service Delegate

@MainActor
final class MockServiceDelegate: SmartDockServiceDelegate {
    var stateUpdates: [(hasExternal: Bool, timestamp: Date)] = []

    func serviceDidUpdateState(_ service: SmartDockService, hasExternal: Bool) {
        stateUpdates.append((hasExternal: hasExternal, timestamp: Date()))
    }
}

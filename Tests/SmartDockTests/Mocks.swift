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

@MainActor
final class MockDockController: DockControlling {
    var onExternalConfigChanged: ((DockConfiguration) -> Void)?

    var applyCallCount = 0
    var lastAppliedConfig: DockConfiguration?
    var mockSystemConfig = DockConfiguration()
    var startObservingCallCount = 0
    var stopObservingCallCount = 0

    private(set) var lastApplyOutcome: DockApplyOutcome?

    /// Properties the mock should pretend the Dock silently refused, so tests can
    /// reproduce the case where AppleScript succeeds but nothing changes.
    var mockRejectedProperties: [DockProperty] = []

    /// Autohide state resulting from the last applied config.
    var autoHideState: Bool { lastAppliedConfig?.autohide ?? false }

    @discardableResult
    func apply(_ config: DockConfiguration) -> Bool {
        applyCallCount += 1
        lastAppliedConfig = config

        let requested = config.differences(from: mockSystemConfig)
        lastApplyOutcome = DockApplyOutcome(
            requested: requested,
            rejected: requested.filter { mockRejectedProperties.contains($0) })

        return true
    }

    func readSystemConfig() -> DockConfiguration {
        mockSystemConfig
    }

    func startObservingSystemChanges() {
        startObservingCallCount += 1
    }

    func stopObservingSystemChanges() {
        stopObservingCallCount += 1
    }

    /// Simulates an external dock settings change (e.g. via System Settings).
    func simulateExternalDockChange(_ config: DockConfiguration) {
        onExternalConfigChanged?(config)
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

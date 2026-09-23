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

    var onApplyVerified: ((DockApplyOutcome, DockConfiguration) -> Void)?

    /// Reports a verification result, the way the real controller does a second
    /// after applying.
    func simulateApplyVerified(_ outcome: DockApplyOutcome, actual: DockConfiguration) {
        lastApplyOutcome = outcome
        onApplyVerified?(outcome, actual)
    }

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
        let rejected = requested.filter { mockRejectedProperties.contains($0) }
        lastApplyOutcome = DockApplyOutcome(requested: requested, rejected: rejected)

        // The Dock now holds everything it accepted, and the old value of whatever it
        // refused. Reporting that back is what the real controller does a second after
        // the apply — without it, `handleApplyVerified` never runs and every service
        // test is blind to what happens after a refusal, which is how a real bug in
        // the auto-hide toggle stayed invisible to a green suite.
        mockSystemConfig = Self.accepted(config, rejecting: rejected, keeping: mockSystemConfig)
        onApplyVerified?(lastApplyOutcome!, mockSystemConfig)

        return true
    }

    /// `config` with every refused property taken back from `previous`. Exhaustive on
    /// purpose: a new `DockProperty` must say how the Dock would refuse it.
    private static func accepted(
        _ config: DockConfiguration, rejecting rejected: [DockProperty],
        keeping previous: DockConfiguration
    ) -> DockConfiguration {
        rejected.reduce(config) { result, property in
            switch property {
            case .position: result.with(position: previous.position)
            case .autohide: result.with(autohide: previous.autohide)
            case .iconSize: result.with(iconSize: previous.iconSize)
            case .magnification: result.with(magnification: previous.magnification)
            case .magnificationSize: result.with(magnificationSize: previous.magnificationSize)
            case .minimizeEffect: result.with(minimizeEffect: previous.minimizeEffect)
            case .animatesLaunch: result.with(animatesLaunch: previous.animatesLaunch)
            case .showsRecents: result.with(showsRecents: previous.showsRecents)
            case .showsIndicators: result.with(showsIndicators: previous.showsIndicators)
            case .minimizesToApplication:
                result.with(minimizesToApplication: previous.minimizesToApplication)
            }
        }
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

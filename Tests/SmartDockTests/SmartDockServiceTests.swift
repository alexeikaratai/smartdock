import XCTest
@testable import SmartDockCore

@MainActor
final class SmartDockServiceTests: XCTestCase {

    private var monitor: MockDisplayMonitor!
    private var dock: MockDockController!
    private var delegate: MockServiceDelegate!
    private var service: SmartDockService!

    override func setUp() async throws {
        monitor = MockDisplayMonitor()
        dock = MockDockController()
        delegate = MockServiceDelegate()
        service = SmartDockService(displayMonitor: monitor, dockController: dock)
        service.delegate = delegate
    }

    override func tearDown() async throws {
        service.stop()
    }

    // MARK: - Start / Stop

    func testStartBeginsMonitoring() {
        service.start()
        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(monitor.startCallCount, 1)
    }

    func testStopEndsMonitoring() {
        service.start()
        service.stop()
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(monitor.stopCallCount, 1)
    }

    func testDoubleStartIsNoop() {
        service.start()
        service.start()
        XCTAssertEqual(monitor.startCallCount, 1)
    }

    func testDoubleStopIsNoop() {
        service.start()
        service.stop()
        service.stop()
        XCTAssertEqual(monitor.stopCallCount, 1)
    }

    // MARK: - Display Change → Dock Config Applied

    func testStartAppliesConfig() {
        monitor.mockExternalCount = 0
        service.start()

        XCTAssertEqual(dock.applyCallCount, 1, "Should apply config on start")
        XCTAssertNotNil(dock.lastAppliedConfig)
    }

    func testExternalConnectedAppliesExternalConfig() {
        monitor.mockExternalCount = 0
        service.start()

        monitor.simulateDisplayChange(externalCount: 1)

        XCTAssertTrue(service.hasExternalDisplay)
        XCTAssertEqual(dock.applyCallCount, 2) // start + change
    }

    func testExternalDisconnectedAppliesBuiltinConfig() {
        monitor.mockExternalCount = 1
        service.start()

        monitor.simulateDisplayChange(externalCount: 0)

        XCTAssertFalse(service.hasExternalDisplay)
        XCTAssertEqual(dock.applyCallCount, 2)
    }

    func testMultipleExternalsStillAppliesConfig() {
        monitor.mockExternalCount = 0
        service.start()

        monitor.simulateDisplayChange(externalCount: 3)
        XCTAssertTrue(service.hasExternalDisplay)
    }

    // MARK: - Delegate

    func testDelegateNotifiedOnStart() {
        monitor.mockExternalCount = 1
        service.start()

        XCTAssertEqual(delegate.stateUpdates.count, 1)
        XCTAssertTrue(delegate.stateUpdates[0].hasExternal)
    }

    func testDelegateNotifiedOnChange() {
        monitor.mockExternalCount = 0
        service.start()

        monitor.simulateDisplayChange(externalCount: 1)
        monitor.simulateDisplayChange(externalCount: 0)

        XCTAssertEqual(delegate.stateUpdates.count, 3) // start + 2 changes
        XCTAssertFalse(delegate.stateUpdates[0].hasExternal)
        XCTAssertTrue(delegate.stateUpdates[1].hasExternal)
        XCTAssertFalse(delegate.stateUpdates[2].hasExternal)
    }

    // MARK: - Disabled State

    func testChangesIgnoredWhenDisabled() {
        monitor.mockExternalCount = 0
        service.start()
        let callsAfterStart = dock.applyCallCount

        service.stop()
        monitor.simulateDisplayChange(externalCount: 1)

        XCTAssertEqual(dock.applyCallCount, callsAfterStart,
                       "Dock should not be touched when service is disabled")
    }

    // MARK: - Refresh

    func testRefreshReappliesConfig() {
        monitor.mockExternalCount = 0
        service.start()
        let callsBefore = dock.applyCallCount

        service.refresh()
        XCTAssertEqual(dock.applyCallCount, callsBefore + 1)
    }

    // MARK: - Config Correctness

    func testExternalConfigHasAutohideOff() {
        let prefs = UserPreferences.shared
        prefs.externalConfig = DockConfiguration(autohide: false)
        monitor.mockExternalCount = 1
        service.start()

        XCTAssertNotNil(dock.lastAppliedConfig)
        XCTAssertFalse(dock.lastAppliedConfig!.autohide,
                       "External mode should have autohide=false (dock visible)")
    }

    func testBuiltinConfigHasAutohideOn() {
        let prefs = UserPreferences.shared
        prefs.builtinConfig = DockConfiguration(autohide: true)
        monitor.mockExternalCount = 0
        service.start()

        XCTAssertNotNil(dock.lastAppliedConfig)
        XCTAssertTrue(dock.lastAppliedConfig!.autohide,
                      "Built-in mode should have autohide=true (dock hidden)")
    }

    func testDisconnectSwitchesToBuiltinConfig() {
        let prefs = UserPreferences.shared
        prefs.externalConfig = DockConfiguration(autohide: false)
        prefs.builtinConfig = DockConfiguration(autohide: true)

        monitor.mockExternalCount = 1
        service.start()

        XCTAssertFalse(dock.lastAppliedConfig!.autohide)

        monitor.simulateDisplayChange(externalCount: 0)

        XCTAssertFalse(service.hasExternalDisplay)
        XCTAssertTrue(dock.lastAppliedConfig!.autohide,
                      "After disconnect, should apply builtin config with autohide=true")
    }

    func testConnectSwitchesToExternalConfig() {
        let prefs = UserPreferences.shared
        prefs.externalConfig = DockConfiguration(autohide: false)
        prefs.builtinConfig = DockConfiguration(autohide: true)

        monitor.mockExternalCount = 0
        service.start()

        XCTAssertTrue(dock.lastAppliedConfig!.autohide)

        monitor.simulateDisplayChange(externalCount: 1)

        XCTAssertTrue(service.hasExternalDisplay)
        XCTAssertFalse(dock.lastAppliedConfig!.autohide,
                       "After connect, should apply external config with autohide=false")
    }

    // MARK: - Space Change Re-apply

    func testSpaceChangeTriggersReapply() {
        // Simulates: fullscreen exit → space change → onConfigurationChanged fires
        monitor.mockExternalCount = 1
        service.start()
        let callsAfterStart = dock.applyCallCount

        // Simulate space change (Mission Control / fullscreen exit)
        // This is what DisplayMonitor.handleSpaceChange does — fires callback
        // without changing the display count
        monitor.onConfigurationChanged?()

        XCTAssertEqual(dock.applyCallCount, callsAfterStart + 1,
                       "Space change should trigger re-apply to fix stuck dock state")
    }

    func testSpaceChangePreservesCorrectMode() {
        // External connected → space change should still apply external config
        monitor.mockExternalCount = 2
        service.start()

        monitor.onConfigurationChanged?()

        XCTAssertTrue(service.hasExternalDisplay)
        XCTAssertFalse(dock.lastAppliedConfig!.autohide,
                       "Space change with external monitors should keep external config")
    }

    func testSpaceChangeIgnoredWhenDisabled() {
        monitor.mockExternalCount = 1
        service.start()
        let callsAfterStart = dock.applyCallCount

        service.stop()
        monitor.onConfigurationChanged?()

        XCTAssertEqual(dock.applyCallCount, callsAfterStart,
                       "Space change should be ignored when service is disabled")
    }

    // MARK: - Rapid State Changes

    func testRapidConnectDisconnect() {
        let prefs = UserPreferences.shared
        prefs.externalConfig = DockConfiguration(autohide: false)
        prefs.builtinConfig = DockConfiguration(autohide: true)

        monitor.mockExternalCount = 0
        service.start()

        monitor.simulateDisplayChange(externalCount: 1)
        monitor.simulateDisplayChange(externalCount: 0)
        monitor.simulateDisplayChange(externalCount: 2)
        monitor.simulateDisplayChange(externalCount: 0)

        XCTAssertFalse(service.hasExternalDisplay)
        XCTAssertTrue(dock.lastAppliedConfig!.autohide,
                      "After rapid changes ending with no external, should be builtin config")
    }

    func testRefreshAfterSpaceChangeFixesDock() {
        // Simulates: external connected → fullscreen → exit → dock stuck
        // → refresh should fix it
        monitor.mockExternalCount = 1
        service.start()

        // Space change (simulating fullscreen exit)
        monitor.onConfigurationChanged?()
        // Manual refresh
        service.refresh()

        XCTAssertFalse(dock.lastAppliedConfig!.autohide,
                       "Refresh with external monitors should apply autohide=false")
    }
}

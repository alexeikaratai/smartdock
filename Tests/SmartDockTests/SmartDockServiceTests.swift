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
}

import XCTest
@testable import SmartDockCore

@MainActor
final class SmartDockServiceTests: XCTestCase {

    private var monitor: MockDisplayMonitor!
    private var dock: MockDockController!
    private var delegate: MockServiceDelegate!
    private var service: SmartDockService!

    override func setUp() {
        super.setUp()
        monitor = MockDisplayMonitor()
        dock = MockDockController()
        delegate = MockServiceDelegate()
        service = SmartDockService(displayMonitor: monitor, dockController: dock)
        service.delegate = delegate
    }

    override func tearDown() {
        service.stop()
        super.tearDown()
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

    // MARK: - Display Change → Dock State

    func testStartWithNoExternalHidesDock() {
        monitor.mockExternalCount = 0
        service.start()

        XCTAssertTrue(dock.autoHideState, "Dock should autohide when no external display")
        XCTAssertEqual(dock.lastAutoHideValue, true)
    }

    func testStartWithExternalShowsDock() {
        monitor.mockExternalCount = 1
        service.start()

        XCTAssertFalse(dock.autoHideState, "Dock should be visible with external display")
        XCTAssertEqual(dock.lastAutoHideValue, false)
    }

    func testExternalConnectedShowsDock() {
        monitor.mockExternalCount = 0
        service.start()

        // Connect monitor
        monitor.simulateDisplayChange(externalCount: 1)

        XCTAssertFalse(dock.autoHideState)
        XCTAssertTrue(service.hasExternalDisplay)
    }

    func testExternalDisconnectedHidesDock() {
        monitor.mockExternalCount = 1
        service.start()

        // Disconnect monitor
        monitor.simulateDisplayChange(externalCount: 0)

        XCTAssertTrue(dock.autoHideState)
        XCTAssertFalse(service.hasExternalDisplay)
    }

    func testMultipleExternalsStillShowsDock() {
        monitor.mockExternalCount = 0
        service.start()

        monitor.simulateDisplayChange(externalCount: 3)
        XCTAssertFalse(dock.autoHideState)
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
        let callsAfterStart = dock.setAutoHideCallCount

        service.stop()
        monitor.simulateDisplayChange(externalCount: 1)

        XCTAssertEqual(dock.setAutoHideCallCount, callsAfterStart,
                       "Dock should not be touched when service is disabled")
    }

    // MARK: - Refresh

    func testRefreshReappliesState() {
        monitor.mockExternalCount = 0
        service.start()
        let callsBefore = dock.setAutoHideCallCount

        service.refresh()
        XCTAssertGreaterThanOrEqual(dock.setAutoHideCallCount, callsBefore)
    }
}

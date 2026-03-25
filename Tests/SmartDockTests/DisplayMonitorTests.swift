import XCTest
@testable import SmartDockCore

@MainActor
final class DisplayMonitorTests: XCTestCase {

    // MARK: - Mock Behavior Validation

    func testMockDefaultsToNoExternal() {
        let monitor = MockDisplayMonitor()
        XCTAssertEqual(monitor.externalDisplayCount(), 0)
        XCTAssertFalse(monitor.hasExternalDisplay())
    }

    func testMockReportsExternalCorrectly() {
        let monitor = MockDisplayMonitor()
        monitor.mockExternalCount = 2
        XCTAssertEqual(monitor.externalDisplayCount(), 2)
        XCTAssertTrue(monitor.hasExternalDisplay())
    }

    func testMockCallbackFiresOnSimulation() {
        let monitor = MockDisplayMonitor()
        var callbackFired = false

        monitor.onConfigurationChanged = {
            callbackFired = true
        }

        monitor.simulateDisplayChange(externalCount: 1)
        XCTAssertTrue(callbackFired)
        XCTAssertEqual(monitor.externalDisplayCount(), 1)
    }

    func testMockTracksStartStopCalls() {
        let monitor = MockDisplayMonitor()
        XCTAssertEqual(monitor.startCallCount, 0)
        XCTAssertEqual(monitor.stopCallCount, 0)

        monitor.start()
        monitor.start()
        XCTAssertEqual(monitor.startCallCount, 2)

        monitor.stop()
        XCTAssertEqual(monitor.stopCallCount, 1)
    }

    // MARK: - Real DisplayMonitor (unit-safe checks)

    func testRealMonitorCanBeInstantiated() {
        let monitor = DisplayMonitor()
        XCTAssertNotNil(monitor)
    }

    func testRealMonitorReturnsNonNegativeCount() {
        let monitor = DisplayMonitor()
        // In CI/test environment can be 0 or more, but not negative
        XCTAssertGreaterThanOrEqual(monitor.externalDisplayCount(), 0)
    }

    func testRealMonitorStartStopDoesNotCrash() {
        let monitor = DisplayMonitor()
        monitor.start()
        monitor.stop()
        // Double stop should also not crash
        monitor.stop()
    }
}

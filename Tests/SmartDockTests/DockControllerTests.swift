import XCTest
@testable import SmartDockCore

@MainActor
final class DockControllerTests: XCTestCase {

    // MARK: - Mock Contract

    func testMockDefaultState() {
        let dock = MockDockController()
        XCTAssertFalse(dock.isAutoHideEnabled())
        XCTAssertEqual(dock.setAutoHideCallCount, 0)
    }

    func testMockTracksSetAutoHide() {
        let dock = MockDockController()

        dock.setAutoHide(true)
        XCTAssertTrue(dock.autoHideState)
        XCTAssertEqual(dock.setAutoHideCallCount, 1)
        XCTAssertEqual(dock.lastAutoHideValue, true)

        dock.setAutoHide(false)
        XCTAssertFalse(dock.autoHideState)
        XCTAssertEqual(dock.setAutoHideCallCount, 2)
        XCTAssertEqual(dock.lastAutoHideValue, false)
    }

    func testMockIsAutoHideReflectsState() {
        let dock = MockDockController()
        dock.autoHideState = true
        XCTAssertTrue(dock.isAutoHideEnabled())
    }

    // MARK: - Real DockController (safe checks)

    func testRealControllerCanBeInstantiated() {
        let dock = DockController()
        XCTAssertNotNil(dock)
    }

    func testRealControllerReadsAutoHideState() {
        let dock = DockController()
        // Just check that it doesn't crash — value depends on the system
        _ = dock.isAutoHideEnabled()
    }

    // MARK: - Integration Scenario

    func testFullCycleWithMock() {
        let dock = MockDockController()

        // Initial state — Dock is visible
        XCTAssertFalse(dock.isAutoHideEnabled())

        // No external monitors → hide
        dock.setAutoHide(true)
        XCTAssertTrue(dock.isAutoHideEnabled())

        // Connected monitor → show
        dock.setAutoHide(false)
        XCTAssertFalse(dock.isAutoHideEnabled())

        XCTAssertEqual(dock.setAutoHideCallCount, 2)
    }
}

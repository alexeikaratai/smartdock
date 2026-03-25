import XCTest
@testable import SmartDockCore

@MainActor
final class DockControllerTests: XCTestCase {

    // MARK: - Mock Contract

    func testMockDefaultState() {
        let dock = MockDockController()
        XCTAssertFalse(dock.isAutoHideEnabled())
        XCTAssertEqual(dock.setAutoHideCallCount, 0)
        XCTAssertEqual(dock.applyCallCount, 0)
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

    func testMockTracksApply() {
        let dock = MockDockController()
        let config = DockConfiguration(autohide: true, position: .left, iconSize: 36)

        dock.apply(config)

        XCTAssertEqual(dock.applyCallCount, 1)
        XCTAssertEqual(dock.lastAppliedConfig, config)
        XCTAssertTrue(dock.autoHideState)
    }

    // MARK: - DockConfiguration

    func testConfigDefaultValues() {
        let config = DockConfiguration()
        XCTAssertFalse(config.autohide)
        XCTAssertEqual(config.position, .bottom)
        XCTAssertEqual(config.iconSize, 48)
        XCTAssertFalse(config.magnification)
        XCTAssertEqual(config.magnificationSize, 64)
    }

    func testConfigClampsIconSize() {
        let small = DockConfiguration(iconSize: 0)
        XCTAssertEqual(small.iconSize, 16)

        let large = DockConfiguration(iconSize: 999)
        XCTAssertEqual(large.iconSize, 128)
    }

    func testConfigClampsMagnificationSize() {
        let small = DockConfiguration(magnificationSize: 0)
        XCTAssertEqual(small.magnificationSize, 16)

        let large = DockConfiguration(magnificationSize: 999)
        XCTAssertEqual(large.magnificationSize, 128)
    }

    func testConfigEquality() {
        let a = DockConfiguration(autohide: true, position: .left, iconSize: 48)
        let b = DockConfiguration(autohide: true, position: .left, iconSize: 48)
        XCTAssertEqual(a, b)

        let c = DockConfiguration(autohide: false, position: .left, iconSize: 48)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Scale Conversion

    func testPixelToScaleMin() {
        let scale = DockController.pixelsToAppleScriptScale(16)
        XCTAssertEqual(scale, 0.0, accuracy: 0.001)
    }

    func testPixelToScaleMax() {
        let scale = DockController.pixelsToAppleScriptScale(128)
        XCTAssertEqual(scale, 1.0, accuracy: 0.001)
    }

    func testPixelToScaleMidpoint() {
        let scale = DockController.pixelsToAppleScriptScale(72)
        XCTAssertEqual(scale, 0.5, accuracy: 0.01)
    }

    func testPixelToScaleClamps() {
        XCTAssertEqual(DockController.pixelsToAppleScriptScale(0), 0.0, accuracy: 0.001)
        XCTAssertEqual(DockController.pixelsToAppleScriptScale(999), 1.0, accuracy: 0.001)
    }

    // MARK: - Real DockController (safe checks)

    func testRealControllerCanBeInstantiated() {
        let dock = DockController()
        XCTAssertNotNil(dock)
    }

    func testRealControllerReadsAutoHideState() {
        let dock = DockController()
        _ = dock.isAutoHideEnabled()
    }

    // MARK: - Integration Scenario

    func testFullCycleWithMock() {
        let dock = MockDockController()

        // Initial state — Dock is visible
        XCTAssertFalse(dock.isAutoHideEnabled())

        // Apply external config (dock visible)
        let externalConfig = DockConfiguration(autohide: false, position: .bottom, iconSize: 48)
        dock.apply(externalConfig)
        XCTAssertFalse(dock.isAutoHideEnabled())

        // Apply builtin config (dock hidden)
        let builtinConfig = DockConfiguration(autohide: true, position: .left, iconSize: 36)
        dock.apply(builtinConfig)
        XCTAssertTrue(dock.isAutoHideEnabled())

        XCTAssertEqual(dock.applyCallCount, 2)
    }
}

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
        let config = DockConfiguration(autohide: true, position: .left, iconSize: 0.18)

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
        XCTAssertEqual(config.iconSize, 0.2857, accuracy: 0.001)
        XCTAssertFalse(config.magnification)
        XCTAssertEqual(config.magnificationSize, 0.4286, accuracy: 0.001)
    }

    func testConfigClampsIconSize() {
        let small = DockConfiguration(iconSize: -1.0)
        XCTAssertEqual(small.iconSize, 0.0, accuracy: 0.001)

        let large = DockConfiguration(iconSize: 5.0)
        XCTAssertEqual(large.iconSize, 1.0, accuracy: 0.001)
    }

    func testConfigClampsMagnificationSize() {
        let small = DockConfiguration(magnificationSize: -1.0)
        XCTAssertEqual(small.magnificationSize, 0.0, accuracy: 0.001)

        let large = DockConfiguration(magnificationSize: 5.0)
        XCTAssertEqual(large.magnificationSize, 1.0, accuracy: 0.001)
    }

    func testConfigEquality() {
        let a = DockConfiguration(autohide: true, position: .left, iconSize: 0.5)
        let b = DockConfiguration(autohide: true, position: .left, iconSize: 0.5)
        XCTAssertEqual(a, b)

        let c = DockConfiguration(autohide: false, position: .left, iconSize: 0.5)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Scale Conversion

    func testPixelToScaleMin() {
        let scale = DockConfiguration.pixelsToScale(16)
        XCTAssertEqual(scale, 0.0, accuracy: 0.001)
    }

    func testPixelToScaleMax() {
        let scale = DockConfiguration.pixelsToScale(128)
        XCTAssertEqual(scale, 1.0, accuracy: 0.001)
    }

    func testPixelToScaleMidpoint() {
        let scale = DockConfiguration.pixelsToScale(72)
        XCTAssertEqual(scale, 0.5, accuracy: 0.01)
    }

    func testPixelToScaleClamps() {
        XCTAssertEqual(DockConfiguration.pixelsToScale(0), 0.0, accuracy: 0.001)
        XCTAssertEqual(DockConfiguration.pixelsToScale(999), 1.0, accuracy: 0.001)
    }

    func testScaleToPixelsRoundTrip() {
        let pixels = DockConfiguration.scaleToPixels(0.5)
        XCTAssertEqual(pixels, 72)

        let min = DockConfiguration.scaleToPixels(0.0)
        XCTAssertEqual(min, 16)

        let max = DockConfiguration.scaleToPixels(1.0)
        XCTAssertEqual(max, 128)
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
        let externalConfig = DockConfiguration(autohide: false, position: .bottom, iconSize: 0.29)
        dock.apply(externalConfig)
        XCTAssertFalse(dock.isAutoHideEnabled())

        // Apply builtin config (dock hidden)
        let builtinConfig = DockConfiguration(autohide: true, position: .left, iconSize: 0.18)
        dock.apply(builtinConfig)
        XCTAssertTrue(dock.isAutoHideEnabled())

        XCTAssertEqual(dock.applyCallCount, 2)
    }

    // MARK: - readSystemConfig

    func testMockReadSystemConfig() {
        let dock = MockDockController()
        let custom = DockConfiguration(autohide: true, position: .right, iconSize: 0.43,
                                        magnification: true, magnificationSize: 0.71)
        dock.mockSystemConfig = custom

        let read = dock.readSystemConfig()
        XCTAssertEqual(read, custom)
    }

    func testRealControllerReadsSystemConfig() {
        let dock = DockController()
        let config = dock.readSystemConfig()
        // Should return valid scale values 0.0–1.0
        XCTAssertTrue((0.0...1.0).contains(config.iconSize))
        XCTAssertTrue((0.0...1.0).contains(config.magnificationSize))
        XCTAssertTrue(DockPosition.allCases.contains(config.position))
    }

    // MARK: - DockConfiguration Edge Cases

    func testConfigAllPositions() {
        for pos in DockPosition.allCases {
            let config = DockConfiguration(position: pos)
            XCTAssertEqual(config.position, pos)
            XCTAssertFalse(pos.displayName.isEmpty)
        }
    }

    func testConfigBoundaryValues() {
        let minConfig = DockConfiguration(iconSize: 0.0, magnificationSize: 0.0)
        XCTAssertEqual(minConfig.iconSize, 0.0, accuracy: 0.001)
        XCTAssertEqual(minConfig.magnificationSize, 0.0, accuracy: 0.001)

        let maxConfig = DockConfiguration(iconSize: 1.0, magnificationSize: 1.0)
        XCTAssertEqual(maxConfig.iconSize, 1.0, accuracy: 0.001)
        XCTAssertEqual(maxConfig.magnificationSize, 1.0, accuracy: 0.001)
    }
}

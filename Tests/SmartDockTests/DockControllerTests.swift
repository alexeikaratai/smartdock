import XCTest
@testable import SmartDockCore

@MainActor
final class DockControllerTests: XCTestCase {

    // MARK: - Mock Contract

    func testMockDefaultState() {
        let dock = MockDockController()
        XCTAssertFalse(dock.autoHideState)
        XCTAssertNil(dock.lastAppliedConfig)
        XCTAssertEqual(dock.applyCallCount, 0)
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

    // MARK: - approximatelyEquals (system sync loop prevention)

    // `DockController.handleExternalChange` uses this to tell our own writes
    // (echoed back through KVO) from real System Settings edits. A false positive
    // makes SmartDock ignore the user; a false negative makes it fight System
    // Settings in a loop.

    func testApproximatelyEqualsIdenticalConfigs() {
        let config = DockConfiguration(autohide: true, position: .left, iconSize: 0.3,
                                       magnification: true, magnificationSize: 0.6)
        XCTAssertTrue(config.approximatelyEquals(config))
    }

    func testApproximatelyEqualsIgnoresSubPixelSizeNoise() {
        // 1px of tilesize is ~0.009 of scale — must not read as a user edit.
        let a = DockConfiguration(iconSize: 0.3000, magnificationSize: 0.6000)
        let b = DockConfiguration(iconSize: 0.3089, magnificationSize: 0.6089)
        XCTAssertTrue(a.approximatelyEquals(b))
        XCTAssertTrue(b.approximatelyEquals(a))
    }

    /// The 0.01 tolerance exists to absorb exactly one pixel of tilesize rounding.
    /// Anchored to real pixel values rather than to 0.01 itself: the comparison is
    /// knife-edge at exactly 0.01 (`abs(0.30 - 0.31) == 0.010000000000000009`), but
    /// tilesize is an integer so a difference that small never occurs in practice.
    func testApproximatelyEqualsAbsorbsOnePixelButNotTwo() {
        let base = DockConfiguration(iconSize: DockConfiguration.pixelsToScale(48))
        let onePixelUp = DockConfiguration(iconSize: DockConfiguration.pixelsToScale(49))
        let twoPixelsUp = DockConfiguration(iconSize: DockConfiguration.pixelsToScale(50))

        XCTAssertTrue(base.approximatelyEquals(onePixelUp))   // ~0.0089 — rounding noise
        XCTAssertFalse(base.approximatelyEquals(twoPixelsUp)) // ~0.0179 — a real edit
    }

    func testApproximatelyEqualsDetectsRealSizeChange() {
        let a = DockConfiguration(iconSize: 0.30)
        let b = DockConfiguration(iconSize: 0.50)
        XCTAssertFalse(a.approximatelyEquals(b))
    }

    func testApproximatelyEqualsDetectsMagnificationSizeChange() {
        let a = DockConfiguration(magnification: true, magnificationSize: 0.40)
        let b = DockConfiguration(magnification: true, magnificationSize: 0.80)
        XCTAssertFalse(a.approximatelyEquals(b))
    }

    func testApproximatelyEqualsDetectsAutohideToggle() {
        let a = DockConfiguration(autohide: false)
        let b = DockConfiguration(autohide: true)
        XCTAssertFalse(a.approximatelyEquals(b))
    }

    func testApproximatelyEqualsDetectsPositionChange() {
        let a = DockConfiguration(position: .bottom)
        XCTAssertFalse(a.approximatelyEquals(DockConfiguration(position: .left)))
        XCTAssertFalse(a.approximatelyEquals(DockConfiguration(position: .right)))
    }

    func testApproximatelyEqualsDetectsMagnificationToggle() {
        let a = DockConfiguration(magnification: false)
        let b = DockConfiguration(magnification: true)
        XCTAssertFalse(a.approximatelyEquals(b))
    }

    /// Unlike `==`, size differences below tolerance must still compare equal.
    func testApproximatelyEqualsIsLooserThanEquatable() {
        let a = DockConfiguration(iconSize: 0.3000)
        let b = DockConfiguration(iconSize: 0.3050)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.approximatelyEquals(b))
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

    // MARK: - Integration Scenario

    func testFullCycleWithMock() {
        let dock = MockDockController()

        // Initial state — Dock is visible
        XCTAssertFalse(dock.autoHideState)

        // Apply external config (dock visible)
        let externalConfig = DockConfiguration(autohide: false, position: .bottom, iconSize: 0.29)
        dock.apply(externalConfig)
        XCTAssertFalse(dock.autoHideState)

        // Apply builtin config (dock hidden)
        let builtinConfig = DockConfiguration(autohide: true, position: .left, iconSize: 0.18)
        dock.apply(builtinConfig)
        XCTAssertTrue(dock.autoHideState)

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

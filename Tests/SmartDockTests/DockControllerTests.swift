import Testing

@testable import SmartDockCore

@Suite("Dock configuration")
@MainActor
struct DockControllerTests {

    // MARK: - Mock Contract

    @Test func mockDefaultState() {
        let dock = MockDockController()

        #expect(!dock.autoHideState)
        #expect(dock.lastAppliedConfig == nil)
        #expect(dock.applyCallCount == 0)
    }

    @Test func mockTracksApply() {
        let dock = MockDockController()
        let config = DockConfiguration(autohide: true, position: .left, iconSize: 0.18)

        dock.apply(config)

        #expect(dock.applyCallCount == 1)
        #expect(dock.lastAppliedConfig == config)
        #expect(dock.autoHideState)
    }

    // MARK: - DockConfiguration

    @Test func configDefaultValues() {
        let config = DockConfiguration()

        #expect(!config.autohide)
        #expect(config.position == .bottom)
        expectClose(config.iconSize, 0.2857, within: 0.001)
        #expect(!config.magnification)
        expectClose(config.magnificationSize, 0.4286, within: 0.001)
    }

    @Test(arguments: [(-1.0, 0.0), (5.0, 1.0)])
    func configClampsIconSize(given: Double, expected: Double) {
        expectClose(DockConfiguration(iconSize: given).iconSize, expected, within: 0.001)
    }

    @Test(arguments: [(-1.0, 0.0), (5.0, 1.0)])
    func configClampsMagnificationSize(given: Double, expected: Double) {
        expectClose(
            DockConfiguration(magnificationSize: given).magnificationSize, expected, within: 0.001)
    }

    @Test func configEquality() {
        let a = DockConfiguration(autohide: true, position: .left, iconSize: 0.5)
        let b = DockConfiguration(autohide: true, position: .left, iconSize: 0.5)
        let c = DockConfiguration(autohide: false, position: .left, iconSize: 0.5)

        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - approximatelyEquals (system sync loop prevention)

    // `DockController.handleExternalChange` uses this to tell our own writes
    // (echoed back through KVO) from real System Settings edits. A false positive
    // makes SmartDock ignore the user; a false negative makes it fight System
    // Settings in a loop.

    @Test func approximatelyEqualsIdenticalConfigs() {
        let config = DockConfiguration(
            autohide: true, position: .left, iconSize: 0.3,
            magnification: true, magnificationSize: 0.6)

        #expect(config.approximatelyEquals(config))
    }

    @Test func approximatelyEqualsIgnoresSubPixelSizeNoise() {
        // 1px of tilesize is ~0.009 of scale — must not read as a user edit.
        let a = DockConfiguration(iconSize: 0.3000, magnificationSize: 0.6000)
        let b = DockConfiguration(iconSize: 0.3089, magnificationSize: 0.6089)

        #expect(a.approximatelyEquals(b))
        #expect(b.approximatelyEquals(a))
    }

    /// The 0.01 tolerance exists to absorb exactly one pixel of tilesize rounding.
    /// Anchored to real pixel values rather than to 0.01 itself: the comparison is
    /// knife-edge at exactly 0.01 (`abs(0.30 - 0.31) == 0.010000000000000009`), but
    /// tilesize is an integer so a difference that small never occurs in practice.
    @Test func approximatelyEqualsAbsorbsOnePixelButNotTwo() {
        let base = DockConfiguration(iconSize: DockConfiguration.pixelsToScale(48))
        let onePixelUp = DockConfiguration(iconSize: DockConfiguration.pixelsToScale(49))
        let twoPixelsUp = DockConfiguration(iconSize: DockConfiguration.pixelsToScale(50))

        #expect(base.approximatelyEquals(onePixelUp))  // ~0.0089 — rounding noise
        #expect(!base.approximatelyEquals(twoPixelsUp))  // ~0.0179 — a real edit
    }

    @Test func approximatelyEqualsDetectsRealSizeChange() {
        #expect(!DockConfiguration(iconSize: 0.30).approximatelyEquals(DockConfiguration(iconSize: 0.50)))
    }

    @Test func approximatelyEqualsDetectsMagnificationSizeChange() {
        let a = DockConfiguration(magnification: true, magnificationSize: 0.40)
        let b = DockConfiguration(magnification: true, magnificationSize: 0.80)

        #expect(!a.approximatelyEquals(b))
    }

    @Test func approximatelyEqualsDetectsAutohideToggle() {
        #expect(
            !DockConfiguration(autohide: false).approximatelyEquals(DockConfiguration(autohide: true)))
    }

    @Test(arguments: [DockPosition.left, .right])
    func approximatelyEqualsDetectsPositionChange(other: DockPosition) {
        #expect(
            !DockConfiguration(position: .bottom)
                .approximatelyEquals(DockConfiguration(position: other)))
    }

    @Test func approximatelyEqualsDetectsMagnificationToggle() {
        let a = DockConfiguration(magnification: false)
        let b = DockConfiguration(magnification: true)

        #expect(!a.approximatelyEquals(b))
    }

    /// Unlike `==`, size differences below tolerance must still compare equal.
    @Test func approximatelyEqualsIsLooserThanEquatable() {
        let a = DockConfiguration(iconSize: 0.3000)
        let b = DockConfiguration(iconSize: 0.3050)

        #expect(a != b)
        #expect(a.approximatelyEquals(b))
    }

    // MARK: - Scale Conversion

    @Test(arguments: [(16, 0.0), (128, 1.0), (0, 0.0), (999, 1.0)])
    func pixelToScaleEndsAndClamping(pixels: Int, expected: Double) {
        expectClose(DockConfiguration.pixelsToScale(pixels), expected, within: 0.001)
    }

    @Test func pixelToScaleMidpoint() {
        expectClose(DockConfiguration.pixelsToScale(72), 0.5, within: 0.01)
    }

    @Test(arguments: [(0.0, 16), (0.5, 72), (1.0, 128)])
    func scaleToPixelsRoundTrip(scale: Double, pixels: Int) {
        #expect(DockConfiguration.scaleToPixels(scale) == pixels)
    }

    // MARK: - Integration Scenario

    @Test func fullCycleWithMock() {
        let dock = MockDockController()
        #expect(!dock.autoHideState, "Dock starts visible")

        dock.apply(DockConfiguration(autohide: false, position: .bottom, iconSize: 0.29))
        #expect(!dock.autoHideState)

        dock.apply(DockConfiguration(autohide: true, position: .left, iconSize: 0.18))
        #expect(dock.autoHideState)

        #expect(dock.applyCallCount == 2)
    }

    // MARK: - readSystemConfig

    @Test func mockReadSystemConfig() {
        let dock = MockDockController()
        let custom = DockConfiguration(
            autohide: true, position: .right, iconSize: 0.43,
            magnification: true, magnificationSize: 0.71)
        dock.mockSystemConfig = custom

        #expect(dock.readSystemConfig() == custom)
    }

    /// The real controller reads the live `com.apple.dock` domain. Only what is
    /// safe to assert without knowing the developer's setup is checked here.
    @Test func realControllerReadsPlausibleValues() {
        let config = DockController().readSystemConfig()

        #expect((0.0...1.0).contains(config.iconSize))
        #expect((0.0...1.0).contains(config.magnificationSize))
        #expect(DockPosition.allCases.contains(config.position))
    }

    // MARK: - DockConfiguration Edge Cases

    @Test(arguments: DockPosition.allCases)
    func everyPositionRoundTripsAndHasALabel(position: DockPosition) {
        #expect(DockConfiguration(position: position).position == position)
        #expect(!position.displayName.isEmpty)
    }

    @Test(arguments: [0.0, 1.0])
    func configAcceptsBoundaryValuesUnchanged(value: Double) {
        let config = DockConfiguration(iconSize: value, magnificationSize: value)

        expectClose(config.iconSize, value, within: 0.001)
        expectClose(config.magnificationSize, value, within: 0.001)
    }
}

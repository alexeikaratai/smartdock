import XCTest

@testable import SmartDockCore

/// Covers the decision half of `DockController.apply` — which properties actually
/// need pushing to the Dock. The AppleScript that carries it out talks to System
/// Events and cannot be exercised here; this is the part with the edge cases.
final class DockDiffTests: XCTestCase {

    // MARK: - Helpers

    /// 48px — the macOS default icon size, expressed the way the app stores it.
    private static let px48 = DockConfiguration.pixelsToScale(48)
    private static let px49 = DockConfiguration.pixelsToScale(49)
    private static let px50 = DockConfiguration.pixelsToScale(50)

    private func config(
        autohide: Bool = false,
        position: DockPosition = .bottom,
        iconSize: Double = DockDiffTests.px48,
        magnification: Bool = false,
        magnificationSize: Double = 0.4286
    ) -> DockConfiguration {
        DockConfiguration(
            autohide: autohide,
            position: position,
            iconSize: iconSize,
            magnification: magnification,
            magnificationSize: magnificationSize)
    }

    // MARK: - Nothing To Do

    /// The whole point of diffing: re-applying an unchanged config must run no
    /// AppleScript at all, or every wake and refresh would flash the Dock.
    func testIdenticalConfigsNeedNoWork() {
        XCTAssertTrue(config().differences(from: config()).isEmpty)
    }

    // MARK: - Single Property

    func testPositionChangeIsDetected() {
        XCTAssertEqual(config(position: .left).differences(from: config(position: .bottom)), [.position])
    }

    func testAutohideChangeIsDetected() {
        XCTAssertEqual(config(autohide: true).differences(from: config(autohide: false)), [.autohide])
    }

    func testIconSizeChangeIsDetected() {
        XCTAssertEqual(config(iconSize: Self.px50).differences(from: config(iconSize: Self.px48)), [.iconSize])
    }

    func testMagnificationToggleIsDetected() {
        XCTAssertEqual(
            config(magnification: true).differences(from: config(magnification: false)), [.magnification])
    }

    func testMagnificationSizeChangeIsDetectedWhenMagnificationIsOn() {
        let target = config(magnification: true, magnificationSize: 0.80)
        let current = config(magnification: true, magnificationSize: 0.40)
        XCTAssertEqual(target.differences(from: current), [.magnificationSize])
    }

    // MARK: - Tolerance

    /// Sizes round-trip through the Dock as integer pixels, so an exact comparison
    /// would report a change on every single apply.
    func testOnePixelOfRoundingNoiseIsAbsorbed() {
        XCTAssertTrue(config(iconSize: Self.px49).differences(from: config(iconSize: Self.px48)).isEmpty)
    }

    func testTwoPixelsIsARealChange() {
        XCTAssertEqual(config(iconSize: Self.px50).differences(from: config(iconSize: Self.px48)), [.iconSize])
    }

    // MARK: - Magnification Guard

    /// Magnified size is invisible while magnification is off. Pushing it would
    /// flash the Dock for a value nobody can see.
    func testMagnificationSizeIsIgnoredWhileMagnificationIsOff() {
        let target = config(magnification: false, magnificationSize: 0.80)
        let current = config(magnification: false, magnificationSize: 0.40)
        XCTAssertTrue(
            target.differences(from: current).isEmpty,
            "magnificationSize must not be applied while magnification is off")
    }

    /// Turning magnification on must carry the size along in the same pass —
    /// otherwise the Dock magnifies to whatever size it last held.
    func testEnablingMagnificationAlsoAppliesItsSize() {
        let target = config(magnification: true, magnificationSize: 0.80)
        let current = config(magnification: false, magnificationSize: 0.40)
        XCTAssertEqual(target.differences(from: current), [.magnification, .magnificationSize])
    }

    // MARK: - The Invariant

    /// `approximatelyEquals` decides "was this our own change echoing back", and
    /// `differences` decides "is there anything to apply". They must answer the
    /// same question identically.
    ///
    /// They did not: `apply` skipped magnificationSize while magnification was off,
    /// but `approximatelyEquals` compared it anyway. A profile with magnification
    /// off and a non-default magnified size was therefore read back as an *external*
    /// edit after every apply, and the stored value was silently overwritten with
    /// the system's. This pins the two together.
    func testEmptyDiffAlwaysAgreesWithApproximateEquality() {
        let matrix = [
            config(),
            config(autohide: true),
            config(position: .left),
            config(position: .right),
            config(iconSize: Self.px50),
            config(iconSize: Self.px49),
            config(magnification: true),
            config(magnification: true, magnificationSize: 0.80),
            config(magnification: false, magnificationSize: 0.80),
            config(autohide: true, position: .right, iconSize: Self.px50, magnification: true),
        ]

        for target in matrix {
            for current in matrix {
                XCTAssertEqual(
                    target.differences(from: current).isEmpty,
                    target.approximatelyEquals(current),
                    """
                    Disagreement between "nothing to apply" and "nothing changed".
                    target=\(target)
                    current=\(current)
                    diff=\(target.differences(from: current))
                    """)
            }
        }
    }

    // MARK: - Ordering & Completeness

    /// Position first, then autohide, then sizes — the order `apply` pushes them.
    func testEveryPropertyIsReportedInApplyOrder() {
        let target = config(
            autohide: true, position: .right, iconSize: Self.px50,
            magnification: true, magnificationSize: 0.80)
        let current = config(
            autohide: false, position: .bottom, iconSize: Self.px48,
            magnification: false, magnificationSize: 0.40)

        XCTAssertEqual(
            target.differences(from: current),
            [.position, .autohide, .iconSize, .magnification, .magnificationSize])
    }

    /// A property that can be diffed but never described would log as a blank.
    func testEveryPropertyHasADistinctDescription() {
        let descriptions = DockProperty.allCases.map { config().describe($0) }
        XCTAssertEqual(Set(descriptions).count, DockProperty.allCases.count)
        XCTAssertFalse(descriptions.contains { $0.isEmpty })
    }
}

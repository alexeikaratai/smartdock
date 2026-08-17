import XCTest

@testable import SmartDockCore

/// Covers the check that answers "did the Dock actually take it?".
///
/// AppleScript returns success as soon as the script runs, so without this the app
/// cannot tell an applied setting from one System Events quietly dropped.
final class DockApplyOutcomeTests: XCTestCase {

    // MARK: - Helpers

    private static let px48 = DockConfiguration.pixelsToScale(48)
    private static let px64 = DockConfiguration.pixelsToScale(64)

    private func config(
        autohide: Bool = false,
        position: DockPosition = .bottom,
        iconSize: Double = DockApplyOutcomeTests.px48,
        magnification: Bool = false,
        magnificationSize: Double = 0.4286
    ) -> DockConfiguration {
        DockConfiguration(
            autohide: autohide, position: position, iconSize: iconSize,
            magnification: magnification, magnificationSize: magnificationSize)
    }

    // MARK: - Everything Landed

    func testOutcomeIsCompleteWhenTheDockMatchesWhatWasAsked() {
        let target = config(autohide: true, position: .left)

        let outcome = DockApplyOutcome.verifying(
            target, against: target, requested: [.position, .autohide])

        XCTAssertTrue(outcome.isComplete)
        XCTAssertTrue(outcome.rejected.isEmpty)
    }

    func testNoWorkNeededIsComplete() {
        XCTAssertTrue(DockApplyOutcome.noWorkNeeded.isComplete)
        XCTAssertEqual(DockApplyOutcome.noWorkNeeded.summary, "nothing to apply")
    }

    // MARK: - Silent Refusal

    /// The failure this whole check exists for: the script ran, reported success,
    /// and the setting is simply not there afterwards.
    func testAPropertyTheDockIgnoredIsReported() {
        let target = config(autohide: true, position: .left)
        // Position landed, autohide did not.
        let actual = config(autohide: false, position: .left)

        let outcome = DockApplyOutcome.verifying(
            target, against: actual, requested: [.position, .autohide])

        XCTAssertFalse(outcome.isComplete)
        XCTAssertEqual(outcome.rejected, [.autohide])
    }

    func testSeveralIgnoredPropertiesAreAllReported() {
        let target = config(autohide: true, position: .left, iconSize: Self.px64)
        let actual = config(autohide: false, position: .bottom, iconSize: Self.px48)

        let outcome = DockApplyOutcome.verifying(
            target, against: actual, requested: [.position, .autohide, .iconSize])

        XCTAssertEqual(outcome.rejected, [.position, .autohide, .iconSize])
    }

    // MARK: - Not Our Fault

    /// Someone can change the Dock in System Settings between the push and the
    /// read. That difference is real, but it is not something this apply failed at,
    /// and reporting it would send a bug hunt in the wrong direction.
    func testAPropertyWeNeverAskedForIsNotBlamedOnUs() {
        let target = config(autohide: true, position: .left)
        // Autohide landed; position was changed by someone else afterwards.
        let actual = config(autohide: true, position: .right)

        let outcome = DockApplyOutcome.verifying(
            target, against: actual, requested: [.autohide])

        XCTAssertTrue(outcome.isComplete, "Only requested properties may be reported as rejected")
        XCTAssertTrue(outcome.rejected.isEmpty)
    }

    /// Rejections are a subset of what was requested — always, by construction.
    func testRejectedIsAlwaysASubsetOfRequested() {
        let target = config(autohide: true, position: .left, iconSize: Self.px64)
        let actual = config(autohide: false, position: .bottom, iconSize: Self.px48)

        for requested in [[DockProperty.autohide], [.position], [.position, .iconSize], []] {
            let outcome = DockApplyOutcome.verifying(target, against: actual, requested: requested)
            XCTAssertTrue(
                Set(outcome.rejected).isSubset(of: Set(requested)),
                "rejected \(outcome.rejected) escaped requested \(requested)")
        }
    }

    // MARK: - Tolerance

    /// Sizes round-trip through integer pixels, so a verified size never comes back
    /// bit-identical. Without the shared tolerance every apply would look refused.
    func testSubPixelDriftDoesNotCountAsRefusal() {
        let target = config(iconSize: DockConfiguration.pixelsToScale(48))
        let actual = config(iconSize: DockConfiguration.pixelsToScale(49))

        let outcome = DockApplyOutcome.verifying(target, against: actual, requested: [.iconSize])

        XCTAssertTrue(outcome.isComplete, "1px of rounding is not a refusal")
    }

    // MARK: - Summary

    func testSummaryNamesWhatWasIgnored() {
        let target = config(autohide: true)
        let actual = config(autohide: false)

        let summary = DockApplyOutcome.verifying(
            target, against: actual, requested: [.autohide]
        ).summary

        XCTAssertTrue(summary.contains("ignored"), summary)
        XCTAssertTrue(summary.contains("autohide"), summary)
    }

    func testSummaryOfASuccessfulApplyNamesWhatChanged() {
        let target = config(position: .left)
        let summary = DockApplyOutcome.verifying(
            target, against: target, requested: [.position]
        ).summary

        XCTAssertTrue(summary.contains("applied"), summary)
        XCTAssertTrue(summary.contains("position"), summary)
    }
}

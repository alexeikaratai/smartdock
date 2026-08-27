import Testing

@testable import SmartDockCore

/// Covers the check that answers "did the Dock actually take it?".
///
/// AppleScript returns success as soon as the script runs, so without this the app
/// cannot tell an applied setting from one System Events quietly dropped.
@Suite("Apply outcome")
struct DockApplyOutcomeTests {

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

    @Test func outcomeIsCompleteWhenTheDockMatchesWhatWasAsked() {
        let target = config(autohide: true, position: .left)

        let outcome = DockApplyOutcome.verifying(
            target, against: target, requested: [.position, .autohide])

        #expect(outcome.isComplete)
        #expect(outcome.rejected.isEmpty)
    }

    @Test func noWorkNeededIsComplete() {
        #expect(DockApplyOutcome.noWorkNeeded.isComplete)
        #expect(DockApplyOutcome.noWorkNeeded.summary == "nothing to apply")
    }

    // MARK: - Silent Refusal

    /// The failure this whole check exists for: the script ran, reported success,
    /// and the setting is simply not there afterwards.
    @Test func aPropertyTheDockIgnoredIsReported() {
        let target = config(autohide: true, position: .left)
        // Position landed, autohide did not.
        let actual = config(autohide: false, position: .left)

        let outcome = DockApplyOutcome.verifying(
            target, against: actual, requested: [.position, .autohide])

        #expect(!outcome.isComplete)
        #expect(outcome.rejected == [.autohide])
    }

    @Test func severalIgnoredPropertiesAreAllReported() {
        let target = config(autohide: true, position: .left, iconSize: Self.px64)
        let actual = config(autohide: false, position: .bottom, iconSize: Self.px48)

        let outcome = DockApplyOutcome.verifying(
            target, against: actual, requested: [.position, .autohide, .iconSize])

        #expect(outcome.rejected == [.position, .autohide, .iconSize])
    }

    // MARK: - Not Our Fault

    /// Someone can change the Dock in System Settings between the push and the
    /// read. That difference is real, but it is not something this apply failed at,
    /// and reporting it would send a bug hunt in the wrong direction.
    @Test func aPropertyWeNeverAskedForIsNotBlamedOnUs() {
        let target = config(autohide: true, position: .left)
        // Autohide landed; position was changed by someone else afterwards.
        let actual = config(autohide: true, position: .right)

        let outcome = DockApplyOutcome.verifying(
            target, against: actual, requested: [.autohide])

        #expect(outcome.isComplete, "Only requested properties may be reported as rejected")
        #expect(outcome.rejected.isEmpty)
    }

    /// Rejections are a subset of what was requested — always, by construction.
    @Test(arguments: [[DockProperty.autohide], [.position], [.position, .iconSize], []])
    func rejectedIsAlwaysASubsetOfRequested(requested: [DockProperty]) {
        let target = config(autohide: true, position: .left, iconSize: Self.px64)
        let actual = config(autohide: false, position: .bottom, iconSize: Self.px48)

        let outcome = DockApplyOutcome.verifying(target, against: actual, requested: requested)

        #expect(
            Set(outcome.rejected).isSubset(of: Set(requested)),
            "rejected \(outcome.rejected) escaped requested \(requested)")
    }

    // MARK: - Tolerance

    /// Sizes round-trip through integer pixels, so a verified size never comes back
    /// bit-identical. Without the shared tolerance every apply would look refused.
    @Test func subPixelDriftDoesNotCountAsRefusal() {
        let target = config(iconSize: DockConfiguration.pixelsToScale(48))
        let actual = config(iconSize: DockConfiguration.pixelsToScale(49))

        let outcome = DockApplyOutcome.verifying(target, against: actual, requested: [.iconSize])

        #expect(outcome.isComplete, "1px of rounding is not a refusal")
    }

    // MARK: - Summary

    @Test func summaryNamesWhatWasIgnored() {
        let summary = DockApplyOutcome.verifying(
            config(autohide: true), against: config(autohide: false), requested: [.autohide]
        ).summary

        #expect(summary.contains("ignored"), "\(summary)")
        #expect(summary.contains("autohide"), "\(summary)")
    }

    @Test func summaryOfASuccessfulApplyNamesWhatChanged() {
        let target = config(position: .left)

        let summary = DockApplyOutcome.verifying(
            target, against: target, requested: [.position]
        ).summary

        #expect(summary.contains("applied"), "\(summary)")
        #expect(summary.contains("position"), "\(summary)")
    }
}

import Foundation
import Testing

@testable import SmartDockCore

/// Exercises `DockController.apply` end to end — including the read-back that
/// establishes whether the Dock honoured the change.
///
/// Both the preferences domain and the script runner are injected, so this never
/// touches the developer's real Dock. Without that injection the only way to
/// check this path was by hand, which is exactly how it stayed unverified.
@Suite("Apply verification")
@MainActor
struct DockApplyVerificationTests {

    /// Far below the production 1s — the delay exists to let the Dock settle, and
    /// there is no Dock here.
    private let delay: TimeInterval = 0.05

    /// Waits past the verification delay, letting the main queue run it.
    private func waitForVerification() async throws {
        try await Task.sleep(nanoseconds: UInt64(delay * 4 * 1_000_000_000))
    }

    // MARK: - A Dock That Accepts

    @Test func verificationConfirmsAChangeTheDockHonoured() async throws {
        let store = InMemoryDefaults()
        store.set("bottom", forKey: "orientation")

        // A Dock that does what it is told.
        let controller = DockController(
            openDefaults: { store }, verificationDelay: delay,
            runScript: { _ in
                store.set("left", forKey: "orientation")
                return true

            })

        controller.apply(DockConfiguration(position: .left))
        try await waitForVerification()

        let outcome = try #require(controller.lastApplyOutcome)
        #expect(outcome.requested == [.position])
        #expect(outcome.isComplete, "The Dock took the change; nothing should be reported rejected")
    }

    // MARK: - A Dock That Silently Refuses

    /// The failure the whole feature exists for: the script runs, reports success,
    /// and the setting is simply not there afterwards. Before this check the app
    /// logged "applied" and had no idea.
    @Test func verificationCatchesASilentlyRefusedChange() async throws {
        let store = InMemoryDefaults()
        store.set("bottom", forKey: "orientation")

        // A Dock that reports success and changes nothing.
        let controller = DockController(openDefaults: { store }, verificationDelay: delay, runScript: { _ in true })

        controller.apply(DockConfiguration(position: .left))
        try await waitForVerification()

        let outcome = try #require(controller.lastApplyOutcome)
        #expect(!outcome.isComplete)
        #expect(outcome.rejected == [.position])
    }

    /// `apply` still returns true — the script did run. The two answers are
    /// genuinely different questions, and conflating them is the original bug.
    @Test func applyStillReportsScriptSuccessEvenWhenTheDockRefused() async throws {
        let store = InMemoryDefaults()
        store.set("bottom", forKey: "orientation")

        let controller = DockController(openDefaults: { store }, verificationDelay: delay, runScript: { _ in true })

        #expect(controller.apply(DockConfiguration(position: .left)))

        try await waitForVerification()
        #expect(!(try #require(controller.lastApplyOutcome).isComplete))
    }

    // MARK: - Nothing To Do

    @Test func anApplyWithNoChangesRecordsNoWorkAndRunsNoScript() async throws {
        let store = InMemoryDefaults()
        store.set("left", forKey: "orientation")
        store.set(48, forKey: "tilesize")

        var scriptCount = 0
        let controller = DockController(
            openDefaults: { store }, verificationDelay: delay,
            runScript: { _ in
                scriptCount += 1
                return true

            })

        let target = DockConfiguration(position: .left, iconSize: DockConfiguration.pixelsToScale(48))
        controller.apply(target)

        #expect(scriptCount == 0, "A matching config must not poke the Dock at all")
        #expect(controller.lastApplyOutcome == .noWorkNeeded)
    }

    // MARK: - Superseded Applies

    /// A second apply arriving before the first was verified must not leave the
    /// earlier, now-stale result behind.
    @Test func onlyTheMostRecentApplyIsVerified() async throws {
        let store = InMemoryDefaults()
        store.set("bottom", forKey: "orientation")

        let controller = DockController(
            openDefaults: { store }, verificationDelay: delay,
            runScript: { _ in
                store.set("right", forKey: "orientation")
                return true

            })

        controller.apply(DockConfiguration(position: .left))  // will be superseded
        controller.apply(DockConfiguration(position: .right))  // this one lands
        try await waitForVerification()

        let outcome = try #require(controller.lastApplyOutcome)
        #expect(outcome.isComplete, "The result must describe the last apply, not the abandoned one")
    }
}

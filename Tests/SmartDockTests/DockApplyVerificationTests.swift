import XCTest

@testable import SmartDockCore

/// Scratch domain standing in for `com.apple.dock`.
private let verifySuiteName = "com.smartdock.tests.verify"

/// Exercises `DockController.apply` end to end — including the read-back that
/// establishes whether the Dock honoured the change.
///
/// Both the preferences domain and the script runner are injected, so this never
/// touches the developer's real Dock. Without that injection the only way to
/// check this path was by hand, which is exactly how it stayed unverified.
@MainActor
final class DockApplyVerificationTests: XCTestCase {

    /// Far below the production 1s — the delay exists to let the Dock settle, and
    /// there is no Dock here.
    private let delay: TimeInterval = 0.05

    override func setUp() {
        super.setUp()
        Self.clearScratchDomain()
    }

    override func tearDown() {
        Self.clearScratchDomain()
        super.tearDown()
    }

    private nonisolated static func clearScratchDomain() {
        UserDefaults.standard.removePersistentDomain(forName: verifySuiteName)
        let path = ("~/Library/Preferences/\(verifySuiteName).plist" as NSString).expandingTildeInPath
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Waits past the verification delay, letting the main queue run it.
    private func waitForVerification() async throws {
        try await Task.sleep(nanoseconds: UInt64(delay * 4 * 1_000_000_000))
    }

    // MARK: - A Dock That Accepts

    func testVerificationConfirmsAChangeTheDockHonoured() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: verifySuiteName))
        defaults.set("bottom", forKey: "orientation")

        // A Dock that does what it is told.
        let controller = DockController(suiteName: verifySuiteName, verificationDelay: delay) { _ in
            defaults.set("left", forKey: "orientation")
            return true
        }

        controller.apply(DockConfiguration(position: .left))
        try await waitForVerification()

        let outcome = try XCTUnwrap(controller.lastApplyOutcome)
        XCTAssertEqual(outcome.requested, [.position])
        XCTAssertTrue(outcome.isComplete, "The Dock took the change; nothing should be reported rejected")
    }

    // MARK: - A Dock That Silently Refuses

    /// The failure the whole feature exists for: the script runs, reports success,
    /// and the setting is simply not there afterwards. Before this check the app
    /// logged "applied" and had no idea.
    func testVerificationCatchesASilentlyRefusedChange() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: verifySuiteName))
        defaults.set("bottom", forKey: "orientation")

        // A Dock that reports success and changes nothing.
        let controller = DockController(suiteName: verifySuiteName, verificationDelay: delay) { _ in true }

        controller.apply(DockConfiguration(position: .left))
        try await waitForVerification()

        let outcome = try XCTUnwrap(controller.lastApplyOutcome)
        XCTAssertFalse(outcome.isComplete)
        XCTAssertEqual(outcome.rejected, [.position])
    }

    /// `apply` still returns true — the script did run. The two answers are
    /// genuinely different questions, and conflating them is the original bug.
    func testApplyStillReportsScriptSuccessEvenWhenTheDockRefused() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: verifySuiteName))
        defaults.set("bottom", forKey: "orientation")

        let controller = DockController(suiteName: verifySuiteName, verificationDelay: delay) { _ in true }

        XCTAssertTrue(controller.apply(DockConfiguration(position: .left)))

        try await waitForVerification()
        XCTAssertFalse(try XCTUnwrap(controller.lastApplyOutcome).isComplete)
    }

    // MARK: - Nothing To Do

    func testAnApplyWithNoChangesRecordsNoWorkAndRunsNoScript() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: verifySuiteName))
        defaults.set("left", forKey: "orientation")
        defaults.set(48, forKey: "tilesize")

        var scriptCount = 0
        let controller = DockController(suiteName: verifySuiteName, verificationDelay: delay) { _ in
            scriptCount += 1
            return true
        }

        let target = DockConfiguration(position: .left, iconSize: DockConfiguration.pixelsToScale(48))
        controller.apply(target)

        XCTAssertEqual(scriptCount, 0, "A matching config must not poke the Dock at all")
        XCTAssertEqual(controller.lastApplyOutcome, .noWorkNeeded)
    }

    // MARK: - Superseded Applies

    /// A second apply arriving before the first was verified must not leave the
    /// earlier, now-stale result behind.
    func testOnlyTheMostRecentApplyIsVerified() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: verifySuiteName))
        defaults.set("bottom", forKey: "orientation")

        let controller = DockController(suiteName: verifySuiteName, verificationDelay: delay) { _ in
            defaults.set("right", forKey: "orientation")
            return true
        }

        controller.apply(DockConfiguration(position: .left))  // will be superseded
        controller.apply(DockConfiguration(position: .right))  // this one lands
        try await waitForVerification()

        let outcome = try XCTUnwrap(controller.lastApplyOutcome)
        XCTAssertTrue(outcome.isComplete, "The result must describe the last apply, not the abandoned one")
    }
}

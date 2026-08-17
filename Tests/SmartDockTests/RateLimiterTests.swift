import XCTest

@testable import SmartDockCore

/// Timing logic that used to live in the app target, where nothing could reach it.
/// Time is injected, so the interval edges are checked exactly rather than by
/// sleeping and hoping.
final class RateLimiterTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Rate Limiter

    /// Nothing has run yet, so nothing is running too often.
    func testFirstCallIsAlwaysAllowed() {
        var limiter = RateLimiter(interval: 1.0)
        XCTAssertTrue(limiter.allow(at: t0))
    }

    func testSecondCallWithinTheIntervalIsBlocked() {
        var limiter = RateLimiter(interval: 1.0)
        XCTAssertTrue(limiter.allow(at: t0))
        XCTAssertFalse(limiter.allow(at: t0.addingTimeInterval(0.9)))
    }

    /// Exactly at the interval counts as elapsed — `< interval` blocks, not `<=`.
    func testCallExactlyAtTheIntervalIsAllowed() {
        var limiter = RateLimiter(interval: 1.0)
        XCTAssertTrue(limiter.allow(at: t0))
        XCTAssertTrue(limiter.allow(at: t0.addingTimeInterval(1.0)))
    }

    /// The classic way to get this wrong: measuring from the last *attempt* rather
    /// than the last allowed run. A key held down would then never fire again,
    /// because every blocked attempt keeps pushing the deadline out.
    func testBlockedAttemptsDoNotPushTheDeadlineOut() {
        var limiter = RateLimiter(interval: 1.0)
        XCTAssertTrue(limiter.allow(at: t0))

        // A stream of blocked attempts...
        for offset in stride(from: 0.1, through: 0.9, by: 0.1) {
            XCTAssertFalse(limiter.allow(at: t0.addingTimeInterval(offset)))
        }

        // ...must not delay the moment the interval is genuinely up.
        XCTAssertTrue(
            limiter.allow(at: t0.addingTimeInterval(1.0)),
            "Deadline must be measured from the last allowed call, not the last attempt")
    }

    func testResetAllowsImmediately() {
        var limiter = RateLimiter(interval: 10.0)
        XCTAssertTrue(limiter.allow(at: t0))
        XCTAssertFalse(limiter.allow(at: t0.addingTimeInterval(1)))

        limiter.reset()
        XCTAssertTrue(limiter.allow(at: t0.addingTimeInterval(1)))
    }

    // MARK: - Profile Switch Announcer

    func testFirstSwitchIsAnnounced() {
        var announcer = ProfileSwitchAnnouncer(cooldown: 3.0)
        XCTAssertTrue(announcer.shouldAnnounce(hasExternal: true, at: t0))
    }

    /// Re-applying the same profile is not news — settings changes within a profile
    /// re-post the state notification and must not each raise a banner.
    func testUnchangedProfileIsNotAnnouncedAgain() {
        var announcer = ProfileSwitchAnnouncer(cooldown: 3.0)
        XCTAssertTrue(announcer.shouldAnnounce(hasExternal: true, at: t0))
        XCTAssertFalse(announcer.shouldAnnounce(hasExternal: true, at: t0.addingTimeInterval(60)))
    }

    func testRapidFlipFlopIsSuppressed() {
        var announcer = ProfileSwitchAnnouncer(cooldown: 3.0)
        XCTAssertTrue(announcer.shouldAnnounce(hasExternal: true, at: t0))
        XCTAssertFalse(
            announcer.shouldAnnounce(hasExternal: false, at: t0.addingTimeInterval(0.5)),
            "A monitor bouncing during connect must not produce a second banner")
    }

    /// The reason the announced state is recorded only on a real announcement.
    ///
    /// A state that was suppressed by the cooldown was never shown to anyone. If it
    /// counted as announced, the switch that finally settles on it would be
    /// dismissed as a duplicate and the user would never be told at all.
    func testAStateSuppressedByCooldownIsStillAnnouncedOnceThingsSettle() {
        var announcer = ProfileSwitchAnnouncer(cooldown: 3.0)

        XCTAssertTrue(announcer.shouldAnnounce(hasExternal: true, at: t0))
        XCTAssertFalse(announcer.shouldAnnounce(hasExternal: false, at: t0.addingTimeInterval(1)))

        XCTAssertTrue(
            announcer.shouldAnnounce(hasExternal: false, at: t0.addingTimeInterval(10)),
            "The user was never told about built-in — it must not count as already announced")
    }

    func testGenuineSwitchAfterCooldownIsAnnounced() {
        var announcer = ProfileSwitchAnnouncer(cooldown: 3.0)
        XCTAssertTrue(announcer.shouldAnnounce(hasExternal: true, at: t0))
        XCTAssertTrue(announcer.shouldAnnounce(hasExternal: false, at: t0.addingTimeInterval(5)))
        XCTAssertTrue(announcer.shouldAnnounce(hasExternal: true, at: t0.addingTimeInterval(10)))
    }
}

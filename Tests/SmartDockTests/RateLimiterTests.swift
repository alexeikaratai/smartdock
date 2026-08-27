import Foundation
import Testing

@testable import SmartDockCore

/// Timing logic that used to live in the app target, where nothing could reach it.
/// Time is injected, so the interval edges are checked exactly rather than by
/// sleeping and hoping.
///
/// Nothing here touches shared state, so this suite runs in parallel with the rest.
///
/// Note the `let` before each check: `#expect` evaluates its argument inside a
/// closure, where the captured value is immutable, so a `mutating` call cannot be
/// written inline. Every test of a mutating API has to name the result first.
@Suite("Rate limiting")
struct RateLimiterTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Rate Limiter

    /// Nothing has run yet, so nothing is running too often.
    @Test func firstCallIsAlwaysAllowed() {
        var limiter = RateLimiter(interval: 1.0)

        let first = limiter.allow(at: t0)

        #expect(first)
    }

    @Test func secondCallWithinTheIntervalIsBlocked() {
        var limiter = RateLimiter(interval: 1.0)

        let first = limiter.allow(at: t0)
        let tooSoon = limiter.allow(at: t0.addingTimeInterval(0.9))

        #expect(first)
        #expect(!tooSoon)
    }

    /// Exactly at the interval counts as elapsed — `< interval` blocks, not `<=`.
    @Test func callExactlyAtTheIntervalIsAllowed() {
        var limiter = RateLimiter(interval: 1.0)

        let first = limiter.allow(at: t0)
        let atTheEdge = limiter.allow(at: t0.addingTimeInterval(1.0))

        #expect(first)
        #expect(atTheEdge)
    }

    /// The classic way to get this wrong: measuring from the last *attempt* rather
    /// than the last allowed run. A key held down would then never fire again,
    /// because every blocked attempt keeps pushing the deadline out.
    @Test func blockedAttemptsDoNotPushTheDeadlineOut() {
        var limiter = RateLimiter(interval: 1.0)

        let first = limiter.allow(at: t0)
        #expect(first)

        // A stream of blocked attempts...
        for offset in stride(from: 0.1, through: 0.9, by: 0.1) {
            let blocked = limiter.allow(at: t0.addingTimeInterval(offset))
            #expect(!blocked)
        }

        // ...must not delay the moment the interval is genuinely up.
        let afterInterval = limiter.allow(at: t0.addingTimeInterval(1.0))

        #expect(
            afterInterval,
            "Deadline must be measured from the last allowed call, not the last attempt")
    }

    @Test func resetAllowsImmediately() {
        var limiter = RateLimiter(interval: 10.0)

        let first = limiter.allow(at: t0)
        let blocked = limiter.allow(at: t0.addingTimeInterval(1))
        limiter.reset()
        let afterReset = limiter.allow(at: t0.addingTimeInterval(1))

        #expect(first)
        #expect(!blocked)
        #expect(afterReset)
    }

    // MARK: - Profile Switch Announcer

    @Test func firstSwitchIsAnnounced() {
        var announcer = ProfileSwitchAnnouncer(cooldown: 3.0)

        let announced = announcer.shouldAnnounce(hasExternal: true, at: t0)

        #expect(announced)
    }

    /// Re-applying the same profile is not news — settings changes within a profile
    /// re-post the state notification and must not each raise a banner.
    @Test func unchangedProfileIsNotAnnouncedAgain() {
        var announcer = ProfileSwitchAnnouncer(cooldown: 3.0)

        let first = announcer.shouldAnnounce(hasExternal: true, at: t0)
        let repeated = announcer.shouldAnnounce(hasExternal: true, at: t0.addingTimeInterval(60))

        #expect(first)
        #expect(!repeated)
    }

    @Test func rapidFlipFlopIsSuppressed() {
        var announcer = ProfileSwitchAnnouncer(cooldown: 3.0)

        let first = announcer.shouldAnnounce(hasExternal: true, at: t0)
        let bounced = announcer.shouldAnnounce(hasExternal: false, at: t0.addingTimeInterval(0.5))

        #expect(first)
        #expect(!bounced, "A monitor bouncing during connect must not produce a second banner")
    }

    /// The reason the announced state is recorded only on a real announcement.
    ///
    /// A state that was suppressed by the cooldown was never shown to anyone. If it
    /// counted as announced, the switch that finally settles on it would be
    /// dismissed as a duplicate and the user would never be told at all.
    @Test func aStateSuppressedByCooldownIsStillAnnouncedOnceThingsSettle() {
        var announcer = ProfileSwitchAnnouncer(cooldown: 3.0)

        let first = announcer.shouldAnnounce(hasExternal: true, at: t0)
        let suppressed = announcer.shouldAnnounce(hasExternal: false, at: t0.addingTimeInterval(1))
        let settled = announcer.shouldAnnounce(hasExternal: false, at: t0.addingTimeInterval(10))

        #expect(first)
        #expect(!suppressed)
        #expect(
            settled,
            "The user was never told about built-in — it must not count as already announced")
    }

    @Test func genuineSwitchAfterCooldownIsAnnounced() {
        var announcer = ProfileSwitchAnnouncer(cooldown: 3.0)

        let toExternal = announcer.shouldAnnounce(hasExternal: true, at: t0)
        let toBuiltin = announcer.shouldAnnounce(hasExternal: false, at: t0.addingTimeInterval(5))
        let backToExternal = announcer.shouldAnnounce(hasExternal: true, at: t0.addingTimeInterval(10))

        #expect(toExternal)
        #expect(toBuiltin)
        #expect(backToExternal)
    }
}

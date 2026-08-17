import Foundation

// MARK: - Rate Limiter

/// Allows an action at most once per `interval`.
///
/// The current time is passed in rather than read from the clock, so the exact
/// edges — right at the interval, a hair before it — can be tested without making
/// the suite sleep. Those edges are where limiters are usually subtly wrong.
public struct RateLimiter: Sendable {

    public let interval: TimeInterval

    private var lastAllowed: Date?

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Whether the action may run at `now`, recording the time if it may.
    ///
    /// The first call always passes: nothing has run yet, so nothing is being
    /// run too often.
    public mutating func allow(at now: Date) -> Bool {
        if let last = lastAllowed, now.timeIntervalSince(last) < interval {
            return false
        }
        lastAllowed = now
        return true
    }

    /// Forgets the last run, so the next call passes regardless of timing.
    public mutating func reset() {
        lastAllowed = nil
    }
}

// MARK: - Profile Switch Announcer

/// Decides whether a profile switch is worth showing the user a banner for.
///
/// Two independent reasons to stay quiet: the profile has not actually changed
/// since the last thing announced, and banners must not stack up while a monitor
/// is being plugged and unplugged in quick succession.
///
/// The order matters and is the reason this is a type rather than two `if`s at
/// the call site. The announced state is recorded **only when a banner is
/// actually shown** — recording it alongside a suppressed one would mean a state
/// the user was never told about counts as told, and the next genuine switch back
/// to it gets swallowed as a duplicate.
public struct ProfileSwitchAnnouncer: Sendable {

    private var limiter: RateLimiter
    private var lastAnnounced: Bool?

    public init(cooldown: TimeInterval) {
        limiter = RateLimiter(interval: cooldown)
    }

    /// Whether to announce that the active profile is now external / built-in.
    public mutating func shouldAnnounce(hasExternal: Bool, at now: Date) -> Bool {
        guard lastAnnounced != hasExternal else { return false }
        guard limiter.allow(at: now) else { return false }

        lastAnnounced = hasExternal
        return true
    }
}

import Foundation
import Testing

@testable import SmartDockCore

// MARK: - Floating-Point Comparison

/// Asserts two doubles match within a tolerance.
///
/// `#expect` has no accuracy form, and the codebase compares sizes in 29 places.
/// Spelling out `abs(a - b) <= t` at each of them would be 29 chances to write the
/// comparison backwards or drift the tolerance — mistakes that make a test pass
/// while checking nothing. One helper, one definition.
///
/// The comparison is `<=`, matching what `XCTAssertEqual(_:_:accuracy:)` did:
/// a difference exactly equal to the tolerance is still a match.
func expectClose(
    _ actual: Double,
    _ expected: Double,
    within tolerance: Double = 0.0001,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(actual - expected) <= tolerance,
        comment ?? "\(actual) is not within \(tolerance) of \(expected)",
        sourceLocation: sourceLocation)
}

// MARK: - In-Memory Defaults

/// A `UserDefaults` that never touches disk.
///
/// A real suite domain is owned by `cfprefsd` — a *separate daemon* that flushes it
/// on its own schedule, including after the test process has already exited. No
/// in-process cleanup can win that race: deleting the plist in `deinit`, or even
/// sweeping at `atexit`, still left thousands of files in `~/Library/Preferences`
/// across a few hundred runs. Keeping the values in memory sidesteps the daemon
/// entirely, so a test run leaves nothing behind at all.
///
/// Only the three primitives need overriding — `bool`, `integer`, `double` and
/// `string` are all defined in terms of `object(forKey:)`.
final class InMemoryDefaults: UserDefaults, @unchecked Sendable {

    private var storage: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    /// Emits KVO notifications by hand. `DockPrefsObserver` watches the store with
    /// `addObserver(forKeyPath:)`, and without these the system-sync tests would
    /// observe a store that never announces anything.
    override func set(_ value: Any?, forKey defaultName: String) {
        willChangeValue(forKey: defaultName)
        storage[defaultName] = value
        didChangeValue(forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) {
        willChangeValue(forKey: defaultName)
        storage.removeValue(forKey: defaultName)
        didChangeValue(forKey: defaultName)
    }
}

// MARK: - Isolated Preferences

/// A `UserPreferences` backed by its own throwaway defaults domain.
///
/// Preference-backed suites used to share `UserDefaults.standard`, so one test's
/// setup would wipe keys another was mid-way through reading. The project's answer
/// was to forbid parallel test runs entirely. Giving each test its own domain
/// removes the shared state instead of scheduling around it — which is what lets
/// these suites run in parallel with everything else.
///
/// A class, not a struct, so the domain is torn down when the test that owns it
/// goes out of scope.
///
/// `@MainActor` because `UserPreferences` is — the isolation buys nothing here on
/// its own, but the point was never raw concurrency: it is that no two tests can
/// reach the same stored settings any more.
@MainActor
final class ScratchPreferences {

    let prefs: UserPreferences

    /// The underlying store, for tests that need to plant raw keys — migration
    /// from the old pixel format, for instance.
    let defaults: UserDefaults

    init() {
        let store = InMemoryDefaults()
        defaults = store
        prefs = UserPreferences(defaults: store)
    }
}

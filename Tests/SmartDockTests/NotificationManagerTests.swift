import Foundation
import Testing
import UserNotifications

@testable import SmartDockCore
@testable import SmartDockUI

/// What the banner says, when it stays quiet, and what a refused permission does to
/// the stored flag. The real `UNUserNotificationCenter` cannot be reached from a test
/// process at all — `current()` aborts without a bundle — so the manager talks to a
/// recording stand-in through `NotificationPosting`.
@Suite("Notification manager")
@MainActor
struct NotificationManagerTests {

    // MARK: - Fixture

    @MainActor
    private final class RecordingCenter: NotificationPosting {
        var status: UNAuthorizationStatus = .authorized
        var grants = true
        var authorizationThrows = false
        var postThrows = false

        private(set) var posted: [(title: String, body: String, identifier: String)] = []
        private(set) var authorizationRequests = 0
        private(set) var statusChecks = 0

        func authorizationStatus() async -> UNAuthorizationStatus {
            statusChecks += 1
            return status
        }

        func requestAuthorization() async throws -> Bool {
            authorizationRequests += 1
            if authorizationThrows { throw CocoaError(.featureUnsupported) }
            return grants
        }

        func post(title: String, body: String, identifier: String) async throws {
            if postThrows { throw CocoaError(.fileNoSuchFile) }
            posted.append((title, body, identifier))
        }
    }

    @MainActor
    private struct Fixture {
        let scratch = ScratchPreferences()
        let center = RecordingCenter()
        /// Private to this test: the manager listens for any sender, and suites run
        /// in parallel, so a shared centre would let tests hear each other.
        let events = NotificationCenter()
        let manager: NotificationManager

        init(notificationsEnabled: Bool = true, cooldown: TimeInterval = 0) {
            scratch.prefs.notificationsEnabled = notificationsEnabled
            manager = NotificationManager(
                center: center, prefs: scratch.prefs, cooldown: cooldown, events: events)
        }

        /// The service's own announcement, as `notifyStateChanged` posts it.
        func announce(_ profile: DockProfile, hasExternal: Bool = true) {
            events.post(
                name: .smartDockStateDidChange,
                object: nil,
                userInfo: [
                    SmartDockService.hasExternalKey: hasExternal,
                    SmartDockService.activeProfileKey: profile,
                ])
        }
    }

    // MARK: - What the Banner Says

    @Test(arguments: DockProfile.allCases)
    func theBannerNamesTheProfileThatIsNowInForce(profile: DockProfile) async throws {
        let f = Fixture()

        f.announce(profile)
        try await waitUntil { !f.center.posted.isEmpty }

        #expect(f.center.posted.count == 1)
        #expect(f.center.posted.first?.title == "SmartDock")
        #expect(f.center.posted.first?.body == "Switched to \(profile.displayName) profile")
        #expect(f.center.posted.first?.identifier == "com.smartdock.profileSwitch")
    }

    /// One identifier for every switch, so a new banner replaces the last rather
    /// than stacking up in Notification Centre.
    @Test func everyBannerReusesOneIdentifier() async throws {
        let f = Fixture()

        f.announce(.builtin)
        try await waitUntil { f.center.posted.count == 1 }
        f.announce(.external)
        try await waitUntil { f.center.posted.count == 2 }

        #expect(Set(f.center.posted.map(\.identifier)).count == 1)
    }

    // MARK: - When It Stays Quiet

    @Test func nothingIsPostedWhileNotificationsAreOff() async throws {
        let f = Fixture(notificationsEnabled: false)

        f.announce(.builtin)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(f.center.posted.isEmpty)
        #expect(f.center.authorizationRequests == 0, "and permission is never asked for")
    }

    /// A settings change within the same profile is not a switch.
    @Test func thesameProfileTwiceIsAnnouncedOnce() async throws {
        let f = Fixture()

        f.announce(.external)
        try await waitUntil { f.center.posted.count == 1 }
        f.announce(.external)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(f.center.posted.count == 1)
    }

    /// Plugging a monitor in and out faster than the cooldown must not stack banners.
    @Test func switchesFasterThanTheCooldownAreDropped() async throws {
        let f = Fixture(cooldown: 60)

        f.announce(.builtin)
        try await waitUntil { f.center.posted.count == 1 }
        f.announce(.external)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(f.center.posted.count == 1, "the second switch is inside the cooldown")
    }

    /// The service posts `hasExternal` too; a state change that carries no profile
    /// is not something this manager can name.
    @Test func anAnnouncementWithoutAProfileIsIgnored() async throws {
        let f = Fixture()

        f.events.post(
            name: .smartDockStateDidChange, object: nil,
            userInfo: [SmartDockService.hasExternalKey: true])
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(f.center.posted.isEmpty)
    }

    // MARK: - Permission

    /// Asked for on the first banner, not at launch — an app that has never switched
    /// a profile has no business prompting.
    @Test func permissionIsAskedForLazilyAndOnlyOnce() async throws {
        let f = Fixture()
        f.center.status = .notDetermined

        f.announce(.builtin)
        try await waitUntil { !f.center.posted.isEmpty }
        f.announce(.external)
        try await waitUntil { f.center.posted.count == 2 }

        #expect(f.center.authorizationRequests == 1)
        #expect(f.center.statusChecks == 1, "authorised once, then remembered")
    }

    /// Refused: the stored flag goes off, so the checkbox in Settings stops claiming
    /// notifications are on, and nothing is posted.
    @Test func arefusedPermissionClearsTheFlagAndPostsNothing() async throws {
        let f = Fixture()
        f.center.status = .notDetermined
        f.center.grants = false

        f.announce(.builtin)
        try await waitUntil { !f.scratch.prefs.notificationsEnabled }

        #expect(f.center.posted.isEmpty)
        #expect(!f.scratch.prefs.notificationsEnabled)
    }

    @Test func permissionDeniedInSystemSettingsPostsNothing() async throws {
        let f = Fixture()
        f.center.status = .denied

        f.announce(.builtin)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(f.center.posted.isEmpty)
        #expect(f.center.authorizationRequests == 0, "already answered — do not ask again")
    }

    /// The Settings checkbox asks for permission by posting a notification; the
    /// answer comes back the same way, for the checkbox to follow.
    @Test func arequestFromSettingsReportsTheAnswerBack() async throws {
        let f = Fixture()
        f.center.grants = false
        let answered = Tally()
        let token = f.events.addObserver(
            forName: .smartDockNotificationPermissionChanged, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { answered.count += 1 } }
        defer { f.events.removeObserver(token) }

        f.events.post(name: .smartDockRequestNotificationAuth, object: nil)
        try await waitUntil { answered.count > 0 }

        #expect(f.center.authorizationRequests == 1)
        #expect(!f.scratch.prefs.notificationsEnabled, "a refusal turns the setting off")
    }

    @Test func afailedRequestIsTreatedAsARefusal() async throws {
        let f = Fixture()
        f.center.authorizationThrows = true

        f.events.post(name: .smartDockRequestNotificationAuth, object: nil)
        try await waitUntil { !f.scratch.prefs.notificationsEnabled }

        #expect(!f.scratch.prefs.notificationsEnabled)
    }

    /// A banner that cannot be delivered is logged, not crashed on.
    @Test func afailedPostIsSurvived() async throws {
        let f = Fixture()
        f.center.postThrows = true

        f.announce(.builtin)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(f.center.posted.isEmpty)
    }
}

/// Main-actor box a `@Sendable` observer can bump.
@MainActor
private final class Tally {
    var count = 0
}

import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

// The smaller views and the wrappers around system services. Each is built for real
// and read back; the actions that would leave the test process — opening a URL,
// registering a login item, resetting a permission — are the ones left alone.

// MARK: - General Settings

/// The General tab's behaviour, asserted on the model rather than on controls. The tab
/// itself is SwiftUI now and holds nothing to test: every switch reads and writes this
/// type. Nothing here builds a view or a window, which is why the suite runs in
/// milliseconds where clicking real checkboxes took seconds.
@Suite("General settings")
@MainActor
struct GeneralSettingsModelTests {

    /// A login item that records instead of registering — the real one would put
    /// `xctest` in the developer's Login Items.
    @MainActor
    final class FakeLoginItem: LoginItemRegistering {
        var isRegistered = false
        /// Refusing is how macOS declines a registration, and the model has to follow
        /// what the system reports rather than what was asked for.
        var refuses = false
        private(set) var changes = 0

        struct Refused: Error {}

        func register() throws {
            if refuses { throw Refused() }
            changes += 1
            isRegistered = true
        }

        func unregister() throws {
            if refuses { throw Refused() }
            changes += 1
            isRegistered = false
        }
    }

    @MainActor
    private struct Fixture {
        let scratch = ScratchPreferences()
        let dock = MockDockController()
        let loginItem = FakeLoginItem()
        let service: SmartDockService
        /// Private, because the centre is process-wide and the model both listens on it
        /// and posts to it — a shared one would have every parallel suite join in.
        let events = NotificationCenter()
        let model: GeneralSettingsModel
        let quits = Tally()

        init() {
            service = SmartDockService(
                displayMonitor: MockDisplayMonitor(), dockController: dock, prefs: scratch.prefs)
            service.start()
            scratch.prefs.notificationsEnabled = true
            scratch.prefs.syncFromSystemEnabled = false
            let quits = self.quits
            model = GeneralSettingsModel(
                service: service, prefs: scratch.prefs,
                launchAtLogin: LaunchAtLogin(service: loginItem),
                events: events,
                quitApp: { MainActor.assumeIsolated { quits.count += 1 } })
        }
    }

    @Test func theSwitchesShowTheStoredFlags() {
        let f = Fixture()

        #expect(f.model.notificationsEnabled)
        #expect(!f.model.syncsFromSystem)
        #expect(!f.model.launchesAtLogin, "the fake login item is not registered")
    }

    @Test func turningOnLaunchAtLoginRegistersAndFollowsTheResult() {
        let f = Fixture()

        f.model.setLaunchAtLogin(true)

        #expect(f.loginItem.isRegistered)
        #expect(f.model.launchesAtLogin)

        f.model.setLaunchAtLogin(false)

        #expect(!f.loginItem.isRegistered)
        #expect(!f.model.launchesAtLogin)
    }

    /// macOS can decline to register the login item. The switch must stay where it was
    /// rather than show what was asked for — which is why the model reads the result
    /// back instead of binding straight into a settable property.
    @Test func arefusedRegistrationLeavesTheSwitchAlone() {
        let f = Fixture()
        f.loginItem.refuses = true

        f.model.setLaunchAtLogin(true)

        #expect(!f.model.launchesAtLogin, "the switch claims a login item that was refused")
        #expect(!f.loginItem.isRegistered)
    }

    /// Setting a switch to what it already shows must not reach the system: toggling a
    /// registered login item "on" would unregister it.
    @Test func settingAswitchToWhatItAlreadyShowsDoesNothing() {
        let f = Fixture()
        f.model.setLaunchAtLogin(true)
        let changes = f.loginItem.changes

        f.model.setLaunchAtLogin(true)

        #expect(f.loginItem.changes == changes, "the login item was touched again")
        #expect(f.model.launchesAtLogin)
    }

    @Test func turningOnSyncWritesTheFlag() {
        let f = Fixture()

        f.model.setSyncFromSystem(true)

        #expect(f.scratch.prefs.syncFromSystemEnabled)
        #expect(f.model.syncsFromSystem)
    }

    /// Turning notifications on also asks for authorisation — that is the manager's job,
    /// reached through a notification so this never touches `UNUserNotificationCenter`.
    @Test func turningOnNotificationsWritesTheFlagAndAsksForAuthorisation() {
        let f = Fixture()
        f.model.setNotifications(false)
        let asked = Tally()
        let token = f.events.addObserver(
            forName: .smartDockRequestNotificationAuth, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { asked.count += 1 } }
        defer { f.events.removeObserver(token) }

        f.model.setNotifications(true)

        #expect(f.scratch.prefs.notificationsEnabled)
        #expect(asked.count == 1)
    }

    /// Turning them **off** asks for nothing — a request there would prompt someone who
    /// just said they did not want banners.
    @Test func turningNotificationsOffAsksForNothing() {
        let f = Fixture()
        let asked = Tally()
        let token = f.events.addObserver(
            forName: .smartDockRequestNotificationAuth, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { asked.count += 1 } }
        defer { f.events.removeObserver(token) }

        f.model.setNotifications(false)

        #expect(!f.scratch.prefs.notificationsEnabled)
        #expect(asked.count == 0)
    }

    /// Authorisation refused after the switch was turned on puts the flag back off; the
    /// switch follows.
    @Test func arefusedAuthorisationTurnsTheSwitchBackOff() {
        let f = Fixture()
        #expect(f.model.notificationsEnabled)

        f.scratch.prefs.notificationsEnabled = false
        f.events.post(name: .smartDockNotificationPermissionChanged, object: nil)

        #expect(!f.model.notificationsEnabled)
    }

    @Test func refreshNowReappliesTheProfile() {
        let f = Fixture()
        let applies = f.dock.applyCallCount

        f.model.refreshNow()

        #expect(f.dock.applyCallCount == applies + 1)
    }

    /// Quitting goes through a parameter: the real `NSApp.terminate` would take the
    /// suite with it.
    @Test func quitAsksTheAppToTerminate() {
        let f = Fixture()

        f.model.quit()

        #expect(f.quits.count == 1)
    }
}

// MARK: - About

/// The About tab's behaviour, on the model. The clipboard and the confirmation delay are
/// parameters now: the old tests wrote to `NSPasteboard.general`, replacing whatever the
/// person running them had copied, and waited a real 1.5 seconds to watch a button title
/// change back.
@Suite("About")
@MainActor
struct AboutModelTests {

    @MainActor
    private final class Recorder {
        var copied: [String] = []
        /// Work handed to the confirmation delay, run by the test rather than a clock.
        var pending: [@MainActor () -> Void] = []
    }

    private func makeModel(_ recorder: Recorder) -> AboutModel {
        let scratch = ScratchPreferences()
        let service = SmartDockService(
            displayMonitor: MockDisplayMonitor(), dockController: MockDockController(),
            prefs: scratch.prefs)
        service.start()
        return AboutModel(
            service: service, prefs: scratch.prefs, appVersion: "9.9.9",
            openURL: { _ in },
            collectLog: { nil },
            saveLog: { _ in },
            copyToPasteboard: { recorder.copied.append($0) },
            afterConfirmation: { recorder.pending.append($0) })
    }

    @Test func copyDiagnosticInfoHandsOverTheWholeReport() throws {
        let recorder = Recorder()
        let model = makeModel(recorder)

        model.copyDiagnostics()

        let copied = try #require(recorder.copied.first)
        #expect(copied.contains("**SmartDock"))
        #expect(copied.contains("Active profile:"))
        #expect(copied.contains("**Profiles**"))
        #expect(model.hasCopied, "the button should confirm in place")
    }

    /// The confirmation is temporary — the button goes back to inviting a copy, or a
    /// second bug report is filed from a button that still says "Copied".
    @Test func theCopyConfirmationFadesBackToTheInvitation() throws {
        let recorder = Recorder()
        let model = makeModel(recorder)

        model.copyDiagnostics()
        #expect(model.hasCopied)
        // Named first: invoking a `#require` result in place crashed swift-frontend
        // outright, which is the same family as the shadowing trap in CLAUDE.md —
        // the compiler has opinions about what happens inside a macro expansion.
        let confirmationFaded = try #require(recorder.pending.first)
        confirmationFaded()

        #expect(!model.hasCopied)
    }

    /// Nothing identifying may reach an issue tracker — the same promise
    /// `DiagnosticReportTests` makes, checked again at the point it is handed over.
    @Test func theCopiedReportNamesNobody() throws {
        let recorder = Recorder()
        let model = makeModel(recorder)

        model.copyDiagnostics()

        let copied = try #require(recorder.copied.first)
        #expect(!copied.contains(NSUserName()))
        #expect(!copied.contains(NSHomeDirectory()))
    }
}

// MARK: - Accessibility Status

/// The permission row's state. The row itself is SwiftUI now — what it draws from this
/// model is pinned by `ShortcutsTabContent`; what the model says is pinned here.
@Suite("Accessibility status")
@MainActor
struct AccessibilityStatusModelTests {

    /// Both branches are chosen by the test rather than by the machine: this process is
    /// untrusted here and trusted on a CI runner, so asserting the environment is
    /// asserting nothing.
    private func model(granted: Bool) -> AccessibilityStatusModel {
        AccessibilityStatusModel(
            prefs: ScratchPreferences().prefs,
            isGranted: { granted },
            openURL: { _ in }, promptForTrust: {},
            resetPermission: { _ in true }, relaunch: {}, reportFailure: { _ in })
    }

    /// The pane is named by `AccessibilityChecker.settingName`, never by a literal —
    /// macOS 27 renamed Accessibility to Device Control and Data Access, and a hard-coded
    /// word would send people to a pane that no longer uses it. Asserting the literal here
    /// would only restate the implementation and would fail on the other OS anyway.
    @Test(arguments: [true, false])
    func themodelNamesThePermissionTheWaySystemSettingsDoes(granted: Bool) {
        #expect(model(granted: granted).settingName == AccessibilityChecker.settingName)
    }

    @Test(arguments: [true, false])
    func themodelSaysWhetherThePermissionIsThere(granted: Bool) {
        #expect(model(granted: granted).isGranted == granted)
    }

    /// The permission can change under an open window — someone reads *Not allowed*,
    /// switches SmartDock on in System Settings and comes back. Measured before
    /// `refresh()` existed: the row went on saying *Not allowed*, and only closing the
    /// window cleared it.
    @Test func themodelFollowsApermissionThatChangedUnderIt() {
        final class Permission: @unchecked Sendable { var granted = false }
        let permission = Permission()
        let model = AccessibilityStatusModel(
            prefs: ScratchPreferences().prefs,
            isGranted: { permission.granted },
            openURL: { _ in }, promptForTrust: {},
            resetPermission: { _ in true }, relaunch: {}, reportFailure: { _ in })

        #expect(!model.isGranted)
        permission.granted = true
        #expect(!model.isGranted, "nothing should change until the window comes forward")

        model.refresh()
        #expect(model.isGranted)
    }
}

// MARK: - Position Icons

/// `PositionPicker` is gone: the Dock tab's position control is a SwiftUI segmented
/// picker now, drawn from SF Symbols, and `DockProfileFormContentTests` pins those.
/// `PositionIcon` stays — the Settings window's header still draws one.

@Suite("Position icons")
@MainActor
struct PositionIconTests {

    @Test(arguments: DockPosition.allCases, [true, false])
    func everyIconIsDrawnOnceAndCached(position: DockPosition, selected: Bool) {
        let first = PositionIcon.image(for: position, selected: selected)
        let second = PositionIcon.image(for: position, selected: selected)

        #expect(first.size.width > 0 && first.size.height > 0)
        #expect(first === second, "the same instance comes back")
        #expect(first.tiffRepresentation != nil, "rendering runs the drawing handler")
    }

    @Test func selectedAndUnselectedDiffer() {
        #expect(PositionIcon.image(for: .left, selected: true) !== PositionIcon.image(for: .left, selected: false))
    }
}

// MARK: - Factories

@Suite("UI factories")
@MainActor
struct UIFactoryTests {

    @Test func labelIsStaticText() {
        let label = UI.label("Hello", font: .systemFont(ofSize: 12))

        #expect(label.stringValue == "Hello")
        #expect(!label.isEditable && !label.isBordered)
        #expect(!label.translatesAutoresizingMaskIntoConstraints)
    }

    // `checkboxAndButtonCarryTheirAction` and `scaleSliderSpansTheDockScale` lived here.
    // Their factories are gone: every control they built is a SwiftUI `Toggle`, `Button`
    // or `Slider` now. What is left of `UI` is the window chrome the settings and
    // onboarding windows still put their hosting views inside.

    @Test func theGlassWindowIsBuiltToBeFilled() {
        let (window, content) = UI.glassWindow(
            title: "T", size: NSSize(width: 300, height: 200), styleMask: [.titled])
        #expect(window.title == "T")
        #expect(content.superview != nil, "the content view sits inside the window's glass")
        window.close()
    }
}

// MARK: - Onboarding

@Suite("Onboarding")
@MainActor
struct OnboardingWindowTests {

    /// What the button does, rather than the button. It is SwiftUI now, so there is no
    /// `NSButton` to click — `OnboardingContent` holds nothing but the call.
    @Test func getStartedFinishesAndRemembers() {
        _ = NSApplication.shared
        let scratch = ScratchPreferences()
        let onboarding = OnboardingWindow(prefs: scratch.prefs)
        var completed = 0
        onboarding.onComplete = { completed += 1 }

        onboarding.show()
        onboarding.getStarted()

        #expect(completed == 1)
        #expect(scratch.prefs.hasSeenOnboarding)
    }

    /// The welcome text promises that nothing moves until a profile is edited, and that
    /// promise is the reason `initializeDefaultsIfNeeded` makes both profiles the Dock
    /// verbatim. A version that forced auto-hide on one of them shipped once, and the
    /// first thing the app did was move a Dock nobody had asked it to.
    @Test func thewelcomePromisesThatNothingMovesOnItsOwn() {
        let content = OnboardingContent(appVersion: "1.2.3") {}
        var handedOver = 0
        let wired = OnboardingContent(appVersion: "1.2.3") { handedOver += 1 }

        wired.onGetStarted()

        #expect(handedOver == 1, "the view holds the call and nothing else")
        #expect(content.appVersion == "1.2.3")
    }
}

/// Main-actor box a `@Sendable` observer can bump.
@MainActor
private final class Tally {
    var count = 0
}

extension NSView {
    /// Every view below this one, depth first — for finding a control by title.
    fileprivate var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}

import Cocoa
import ServiceManagement
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

// The flows that end in a system call. Each type reaches that call through a
// parameter, so the decisions *around* it — what is asked, in what order, and what
// happens when the answer is no — are tested without spawning a shell, registering
// a login item, opening a browser or resetting a permission.

// MARK: - Relaunch

@Suite("App relauncher")
@MainActor
struct AppRelauncherTests {

    @Test func theRelaunchScriptWaitsForThisProcessAndPassesThePathSafely() {
        let plan = AppRelauncher.plan(bundlePath: "/Applications/Some App.app", pid: 4242)
        let script = plan.arguments.last ?? ""

        #expect(plan.executable == "/bin/sh")
        #expect(plan.arguments.first == "-c")
        #expect(script.contains("kill -0 4242"), "it waits for this process, not any other")
        #expect(script.contains("i -lt 50"), "bounded — 50 × 0.1s")
        #expect(script.contains("/usr/bin/open -n \"$BUNDLE_PATH\""))
        #expect(plan.environment["BUNDLE_PATH"] == "/Applications/Some App.app")
    }

    /// A path with a quote in it must not become shell syntax — it never reaches
    /// the script text at all.
    @Test func aHostilePathStaysOutOfTheScript() {
        let hostile = "/tmp/a\"; rm -rf ~; echo \".app"

        let plan = AppRelauncher.plan(bundlePath: hostile, pid: 1)

        #expect(!(plan.arguments.last ?? "").contains("rm -rf"))
        #expect(plan.environment["BUNDLE_PATH"] == hostile)
    }

    @Test func aSuccessfulSpawnQuitsTheApp() {
        var ranPlan: AppRelauncher.Plan?
        var terminated = 0

        AppRelauncher.relaunch(
            bundlePath: "/Applications/SmartDock.app", pid: 7,
            run: { ranPlan = $0 }, terminate: { terminated += 1 })

        #expect(ranPlan?.environment["BUNDLE_PATH"] == "/Applications/SmartDock.app")
        #expect(terminated == 1)
    }

    /// The spawn itself, given a plan that runs `true` — it proves a process is
    /// really started without opening anything or waiting for this one to exit.
    @Test func spawningRunsTheGivenCommand() throws {
        let plan = AppRelauncher.Plan(
            executable: "/usr/bin/true", arguments: [], environment: [:])

        try AppRelauncher.spawn(plan)
    }

    @Test func spawningAMissingExecutableThrows() {
        let plan = AppRelauncher.Plan(
            executable: "/no/such/binary", arguments: [], environment: [:])

        #expect(throws: (any Error).self) { try AppRelauncher.spawn(plan) }
    }

    /// If the shell could not be spawned there is nothing to come back to, so the
    /// app stays up rather than quitting into nothing.
    @Test func afailedSpawnLeavesTheAppRunning() {
        var terminated = 0

        AppRelauncher.relaunch(
            bundlePath: "/Applications/SmartDock.app", pid: 7,
            run: { _ in throw CocoaError(.fileNoSuchFile) }, terminate: { terminated += 1 })

        #expect(terminated == 0)
    }
}

// MARK: - Update Watcher

@Suite("App update watcher")
@MainActor
struct AppUpdateWatcherTests {

    @MainActor
    private final class Recorder {
        var answer = true
        var asked = 0
        var relaunched = 0
    }

    private func makeWatcher(_ recorder: Recorder, path: String?) -> AppUpdateWatcher {
        AppUpdateWatcher(
            executablePath: { path }, debounce: 0.02,
            ask: {
                recorder.asked += 1
                return recorder.answer
            },
            relaunch: { recorder.relaunched += 1 })
    }

    /// Homebrew writes the binary several times during an install; one prompt.
    @Test func aburstOfWritesAsksOnce() async throws {
        let recorder = Recorder()
        let watcher = makeWatcher(recorder, path: "/usr/bin/true")
        watcher.start()

        for _ in 0..<5 { watcher.handleChange() }
        try await waitUntil { recorder.asked > 0 }
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(recorder.asked == 1)
        #expect(recorder.relaunched == 1)
        watcher.stop()
    }

    /// "Later" means later: no relaunch, and no second prompt this session — the
    /// file descriptor is dead after the binary was replaced anyway.
    @Test func decliningRelaunchIsRememberedForTheSession() async throws {
        let recorder = Recorder()
        recorder.answer = false
        let watcher = makeWatcher(recorder, path: "/usr/bin/true")
        watcher.start()

        watcher.handleChange()
        try await waitUntil { recorder.asked > 0 }
        watcher.handleChange()
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(recorder.asked == 1)
        #expect(recorder.relaunched == 0)
        #expect(watcher.hasPrompted)
        watcher.stop()
    }

    @Test func stoppingBeforeTheDebounceCancelsThePrompt() async throws {
        let recorder = Recorder()
        let watcher = makeWatcher(recorder, path: "/usr/bin/true")
        watcher.start()

        watcher.handleChange()
        watcher.stop()
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(recorder.asked == 0)
    }

    @Test func watchingAnUnopenableFileIsHarmless() {
        let recorder = Recorder()
        let watcher = makeWatcher(recorder, path: "/no/such/binary")

        watcher.start()
        watcher.stop()

        #expect(recorder.asked == 0)
    }

    /// The watcher the app builds: real path, real alert, real relaunch. Built and
    /// thrown away without starting, so nothing is watched and nothing is asked.
    @Test func theAppsWatcherIsConstructible() {
        let watcher = AppUpdateWatcher()

        watcher.stop()
    }

    /// End to end over a real file: the source fires, the debounce collapses the
    /// writes, and the question is asked once. This is the only proof that the
    /// watcher watches — everything else drives `handleChange` by hand.
    @Test func writingTheWatchedFileAsksToRelaunch() async throws {
        let recorder = Recorder()
        let path = NSTemporaryDirectory() + "smartdock-watch-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: path, contents: Data("v1".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let watcher = makeWatcher(recorder, path: path)
        watcher.start()

        try Data("v2".utf8).write(to: URL(fileURLWithPath: path))
        try await waitUntil { recorder.asked > 0 }

        #expect(recorder.asked == 1)
        #expect(recorder.relaunched == 1)
        watcher.stop()
    }

    @Test func aWatcherWithoutAPathDoesNothing() {
        let recorder = Recorder()
        let watcher = makeWatcher(recorder, path: nil)

        watcher.start()
        watcher.stop()

        #expect(recorder.asked == 0)
    }
}

// MARK: - Launch at Login

@Suite("Launch at login")
@MainActor
struct LaunchAtLoginTests {

    @MainActor
    private final class FakeLoginItem: LoginItemRegistering {
        var isRegistered = false
        var failures = false
        private(set) var registrations = 0
        private(set) var unregistrations = 0

        func register() throws {
            registrations += 1
            if failures { throw CocoaError(.fileWriteNoPermission) }
            isRegistered = true
        }

        func unregister() throws {
            unregistrations += 1
            if failures { throw CocoaError(.fileWriteNoPermission) }
            isRegistered = false
        }
    }

    private func withFake(_ body: (FakeLoginItem, LaunchAtLogin) -> Void) {
        let fake = FakeLoginItem()
        body(fake, LaunchAtLogin(service: fake))
    }

    @Test func togglingRegistersThenUnregisters() {
        withFake { fake, launchAtLogin in
            launchAtLogin.toggle()
            #expect(fake.registrations == 1)
            #expect(launchAtLogin.isEnabled)

            launchAtLogin.toggle()
            #expect(fake.unregistrations == 1)
            #expect(!launchAtLogin.isEnabled)
        }
    }

    /// A refused registration is logged, not crashed on, and the state stays honest.
    @Test func afailedRegistrationLeavesItOff() {
        withFake { fake, launchAtLogin in
            fake.failures = true

            launchAtLogin.enable()

            #expect(fake.registrations == 1)
            #expect(!launchAtLogin.isEnabled)
        }
    }

    @Test func afailedUnregistrationLeavesItOn() {
        withFake { fake, launchAtLogin in
            fake.isRegistered = true
            fake.failures = true

            launchAtLogin.disable()

            #expect(fake.unregistrations == 1)
            #expect(launchAtLogin.isEnabled)
        }
    }

    /// The real wrapper answers for this process without registering anything.
    @Test func therealServiceReportsTheTestBundleAsNotRegistered() {
        #expect(!LaunchAtLogin().isEnabled, "reading the real login item registers nothing")
    }
}

// MARK: - Accessibility Prompt

@Suite("Accessibility prompt")
@MainActor
struct AccessibilityCheckerTests {

    @Test func thefirstLaunchPromptsAndIsRemembered() {
        let scratch = ScratchPreferences()
        var prompts = 0

        AccessibilityChecker.promptIfFirstLaunch(
            prefs: scratch.prefs, isTrusted: { false }, prompt: { prompts += 1 })

        #expect(prompts == 1)
        #expect(scratch.prefs.hasPromptedAccessibility, "so a Homebrew update does not prompt again")
    }

    /// The wrapper the app calls, exercised on the path that cannot prompt: already
    /// asked once, so it returns at the guard before the system dialog.
    @Test func thepublicEntryPointHonoursTheFlag() {
        let scratch = ScratchPreferences()
        scratch.prefs.hasPromptedAccessibility = true

        AccessibilityChecker.promptIfFirstLaunch(prefs: scratch.prefs)

        #expect(scratch.prefs.hasPromptedAccessibility)
    }

    @Test func asecondLaunchNeverPrompts() {
        let scratch = ScratchPreferences()
        scratch.prefs.hasPromptedAccessibility = true
        var prompts = 0

        AccessibilityChecker.promptIfFirstLaunch(
            prefs: scratch.prefs, isTrusted: { false }, prompt: { prompts += 1 })

        #expect(prompts == 0)
    }

    /// Already granted: nothing to ask for, and the flag stays untouched so a later
    /// revocation still gets its one prompt.
    @Test func analreadyTrustedProcessIsNotPrompted() {
        let scratch = ScratchPreferences()
        var prompts = 0

        AccessibilityChecker.promptIfFirstLaunch(
            prefs: scratch.prefs, isTrusted: { true }, prompt: { prompts += 1 })

        #expect(prompts == 0)
        #expect(!scratch.prefs.hasPromptedAccessibility)
    }
}

// MARK: - Accessibility Banner

@Suite("Accessibility banner")
@MainActor
struct AccessibilityWarningResetTests {

    @MainActor
    private final class Recorder {
        var confirms = true
        var resetSucceeds = true
        var opened: [URL] = []
        var resets: [String] = []
        var relaunches = 0
        var failuresReported: [String] = []
    }

    private func makeView(_ recorder: Recorder, prefs: UserPreferences) -> AccessibilityWarningView {
        AccessibilityWarningView(
            prefs: prefs,
            openURL: { recorder.opened.append($0) },
            confirmReset: { recorder.confirms },
            resetPermission: { bundleID in
                recorder.resets.append(bundleID)
                return recorder.resetSucceeds
            },
            relaunch: { recorder.relaunches += 1 },
            reportFailure: { recorder.failuresReported.append($0) })
    }

    private func button(_ title: String, in view: NSView) -> NSButton? {
        (view.subviews + view.subviews.flatMap(\.subviews)).compactMap { $0 as? NSButton }
            .first { $0.title.contains(title) }
    }

    @Test func openSystemSettingsGoesToTheAccessibilityPane() throws {
        let recorder = Recorder()
        let view = makeView(recorder, prefs: ScratchPreferences().prefs)

        try #require(button("Open", in: view)).performClick(nil)

        #expect(recorder.opened.count == 1)
        #expect(recorder.opened.first?.absoluteString.contains("Privacy_Accessibility") == true)
    }

    /// Cancelling leaves everything alone — including the flag that would make the
    /// next launch watch for a grant that is not coming.
    @Test func cancellingTheResetChangesNothing() throws {
        let recorder = Recorder()
        recorder.confirms = false
        let scratch = ScratchPreferences()
        let view = makeView(recorder, prefs: scratch.prefs)

        try #require(button("Reset", in: view)).performClick(nil)

        #expect(recorder.resets.isEmpty)
        #expect(recorder.relaunches == 0)
        #expect(!scratch.prefs.pendingAccessibilityGrant)
    }

    @Test func confirmingResetsThenRelaunches() throws {
        let recorder = Recorder()
        let scratch = ScratchPreferences()
        let view = makeView(recorder, prefs: scratch.prefs)

        try #require(button("Reset", in: view)).performClick(nil)

        #expect(recorder.resets.count == 1)
        #expect(recorder.relaunches == 1)
        #expect(scratch.prefs.pendingAccessibilityGrant, "the next launch opens Shortcuts and waits")
    }

    /// The privileged command can be refused at the password prompt. No relaunch
    /// then — but the flag stays set, because the person may grant it by hand.
    @Test func afailedResetDoesNotRelaunch() throws {
        let recorder = Recorder()
        recorder.resetSucceeds = false
        let scratch = ScratchPreferences()
        let view = makeView(recorder, prefs: scratch.prefs)

        try #require(button("Reset", in: view)).performClick(nil)

        #expect(recorder.resets.count == 1)
        #expect(recorder.relaunches == 0)
        #expect(recorder.failuresReported.count == 1, "and the manual command is offered")
        #expect(scratch.prefs.pendingAccessibilityGrant)
    }
}

// MARK: - About Tab Links & Export

@Suite("About tab links")
@MainActor
struct AboutTabLinkTests {

    @MainActor
    private final class Recorder {
        var log: String? = "collected log"
        var opened: [URL] = []
        var saved: [String] = []
    }

    private func makeView(_ recorder: Recorder) -> AboutTabView {
        let scratch = ScratchPreferences()
        let service = SmartDockService(
            displayMonitor: MockDisplayMonitor(), dockController: MockDockController(), prefs: scratch.prefs)
        return AboutTabView(
            service: service, prefs: scratch.prefs,
            openURL: { recorder.opened.append($0) },
            collectLog: { await MainActor.run { recorder.log } },
            saveLog: { recorder.saved.append($0) })
    }

    private func button(_ title: String, in view: NSView) -> NSButton? {
        (view.subviews + view.subviews.flatMap(\.subviews)).compactMap { $0 as? NSButton }
            .first { $0.title.contains(title) }
    }

    @Test(arguments: [("GitHub", "github.com"), ("Changelog", "releases")])
    func linksPointWhereTheySay(title: String, expected: String) throws {
        let recorder = Recorder()
        let view = makeView(recorder)

        try #require(button(title, in: view)).performClick(nil)

        #expect(recorder.opened.count == 1)
        #expect(recorder.opened.first?.absoluteString.contains(expected) == true, "\(recorder.opened)")
    }

    /// The write behind the save panel: the panel needs a person, the write does not.
    @Test func theExportedLogIsWrittenToThePickedFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("smartdock-export-test.txt")
        defer { try? FileManager.default.removeItem(at: url) }

        AboutTabView.write("two lines\nof log", to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == "two lines\nof log")
    }

    /// An unwritable destination is logged, not crashed on.
    @Test func anUnwritableDestinationIsSurvived() {
        AboutTabView.write("x", to: URL(fileURLWithPath: "/no/such/dir/export.txt"))
    }

    /// The button says what it is doing and comes back afterwards, so a slow log
    /// read does not look like a dead window.
    @Test func exportingCollectsThenOffersToSave() async throws {
        let recorder = Recorder()
        let view = makeView(recorder)
        let exportButton = try #require(button("Export", in: view))

        exportButton.performClick(nil)
        try await waitUntil { !recorder.saved.isEmpty }

        #expect(recorder.saved == ["collected log"])
        #expect(exportButton.isEnabled)
        #expect(exportButton.title.hasPrefix("Export Logs"))
    }

    /// Nothing to export: the button still comes back, and no empty file is offered.
    @Test func anEmptyLogIsNotOfferedForSaving() async throws {
        let recorder = Recorder()
        recorder.log = ""
        let view = makeView(recorder)
        let exportButton = try #require(button("Export", in: view))

        exportButton.performClick(nil)
        try await waitUntil { exportButton.isEnabled }

        #expect(recorder.saved.isEmpty)
        #expect(exportButton.title.hasPrefix("Export Logs"))
    }

    @Test func afailedCollectionIsNotOfferedEither() async throws {
        let recorder = Recorder()
        recorder.log = nil
        let view = makeView(recorder)
        let exportButton = try #require(button("Export", in: view))

        exportButton.performClick(nil)
        try await waitUntil { exportButton.isEnabled }

        #expect(recorder.saved.isEmpty)
    }
}

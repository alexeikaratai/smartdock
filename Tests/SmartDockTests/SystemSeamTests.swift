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
            prefs: scratch.prefs, isTrusted: { false }, showPrompt: { prompts += 1 })

        #expect(prompts == 1)
        #expect(scratch.prefs.hasPromptedAccessibility, "so a Homebrew update does not prompt again")
    }

    /// Returns at the **first** guard, before the system is asked anything at all. The
    /// flag is checked ahead of trust on purpose: a second launch must cost nothing, and
    /// a test that got past this guard with real seams would put the system's own dialog
    /// on screen and leave it waiting for nobody.
    @Test func asecondLaunchNeverPrompts() {
        let scratch = ScratchPreferences()
        scratch.prefs.hasPromptedAccessibility = true
        var prompts = 0
        var trustChecks = 0

        AccessibilityChecker.promptIfFirstLaunch(
            prefs: scratch.prefs,
            isTrusted: {
                trustChecks += 1
                return false
            },
            showPrompt: { prompts += 1 })

        #expect(prompts == 0)
        #expect(trustChecks == 0, "the flag is checked before the system is")
    }

    /// **No test may reach a real system dialog.** CLAUDE.md has said so for a while —
    /// "what the UI suites never do: … prompt for Accessibility" — and one test broke it
    /// anyway, kept safe only by the guard it was testing. A rule nothing checks is a
    /// rule that gets broken, so this reads the suite's own source the way
    /// `AppleScriptCommandTests` reads the shipped `.sdef`: every call to an entry point
    /// that carries a live system seam must name a stub for it.
    ///
    /// The name is **assembled** rather than written out, or this file would match
    /// itself — which it did on the first run.
    @Test func notestReachesTheRealAccessibilityPrompt() throws {
        let entryPoint = "promptIfFirstLaunch" + "("
        // **Every** seam, not the first one. The version of this test written an hour ago
        // looked for `isTrusted` alone, and a call that stubs the trust check but leaves
        // the prompt at its default walks into the real dialog by the shortest path there
        // is: the guards pass, and the last line of the function asks the system. A
        // tripwire that covers one of two live seams reads as protection and is not.
        let stubs = ["isTrusted" + ":", "showPrompt" + ":"]
        let suite = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sources = try FileManager.default
            .contentsOfDirectory(at: suite, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        var bare: [String] = []
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for call in text.components(separatedBy: entryPoint).dropFirst() {
                let arguments = Self.argumentList(of: call)
                let missing = stubs.filter { !arguments.contains($0) }
                guard !missing.isEmpty else { continue }
                bare.append("\(file.lastPathComponent) — no \(missing.joined(separator: ", "))")
            }
        }

        #expect(
            bare.isEmpty,
            """
            these calls leave a system seam at its real default, so the system's \
            Accessibility dialog can appear during a test run and wait for a person who \
            is not watching: \(bare)
            """)
    }

    /// The argument list, up to the parenthesis that closes it rather than the first one
    /// in sight. Scanning to the first `)` ends the call at `ScratchPreferences()` and
    /// reports the stubs after it as missing — a failure that looks like a false alarm,
    /// which is how a tripwire gets weakened instead of heeded.
    private static func argumentList(of call: String) -> String {
        var arguments = ""
        var depth = 0
        for character in call {
            if character == ")" {
                guard depth > 0 else { break }
                depth -= 1
            }
            if character == "(" { depth += 1 }
            arguments.append(character)
        }
        return arguments
    }

    /// Already granted: nothing to ask for, and the flag stays untouched so a later
    /// revocation still gets its one prompt.
    @Test func analreadyTrustedProcessIsNotPrompted() {
        let scratch = ScratchPreferences()
        var prompts = 0

        AccessibilityChecker.promptIfFirstLaunch(
            prefs: scratch.prefs, isTrusted: { true }, showPrompt: { prompts += 1 })

        #expect(prompts == 0)
        #expect(!scratch.prefs.hasPromptedAccessibility)
    }
}

// MARK: - Accessibility Status

@Suite("Accessibility status")
@MainActor
struct AccessibilityGrantTests {

    @MainActor
    private final class Recorder {
        var resetSucceeds = true
        var opened: [URL] = []
        var prompts = 0
        var resets: [String] = []
        var relaunches = 0
        var failuresReported: [String] = []
    }

    private func makeModel(_ recorder: Recorder, prefs: UserPreferences) -> AccessibilityStatusModel {
        AccessibilityStatusModel(
            prefs: prefs,
            // Stated rather than left to the machine: this process is untrusted here and
            // trusted on a CI runner.
            isGranted: { false },
            openURL: { recorder.opened.append($0) },
            promptForTrust: { recorder.prompts += 1 },
            resetPermission: { bundleID in
                recorder.resets.append(bundleID)
                return recorder.resetSucceeds
            },
            relaunch: { recorder.relaunches += 1 },
            reportFailure: { recorder.failuresReported.append($0) })
    }

    /// The whole reason one button replaced two: it clears the entry whether or not the
    /// permission was ever given, since a grant invalidated by an ad-hoc re-signing looks
    /// exactly like no grant from the outside.
    @Test func grantingClearsTheEntryThenRelaunches() {
        let recorder = Recorder()
        let scratch = ScratchPreferences()
        makeModel(recorder, prefs: scratch.prefs).grantAccess()

        #expect(recorder.resets.count == 1)
        #expect(recorder.relaunches == 1)
        #expect(scratch.prefs.pendingAccessibilityGrant, "the next launch asks and watches")
        #expect(
            recorder.prompts == 0,
            "asking from this process is wasted — macOS lists the app for the next one")
    }

    /// When the entry cannot be cleared there is still the never-granted case to serve,
    /// so this process asks and opens the pane, and the manual command covers the rest.
    /// Until the ask was added, a failed clear opened a list with nothing to switch on.
    @Test func agrantThatCannotClearTheEntryStillAsks() {
        let recorder = Recorder()
        recorder.resetSucceeds = false
        let scratch = ScratchPreferences()
        makeModel(recorder, prefs: scratch.prefs).grantAccess()

        #expect(recorder.relaunches == 0)
        #expect(recorder.prompts == 1, "without the prompt the pane lists no SmartDock")
        #expect(recorder.opened.first?.absoluteString.contains("Privacy_Accessibility") == true)
        #expect(recorder.failuresReported.count == 1, "and the manual command is offered")
        #expect(scratch.prefs.pendingAccessibilityGrant)
    }

    /// `tccutil reset Accessibility` with **no** bundle ID resets the permission for
    /// every app on the Mac. Nothing in the app can produce an empty one today — the
    /// call site falls back to a literal — but the real `runTccutil` is the only place
    /// that ever reaches the tool, so the refusal lives there and is pinned here. This
    /// runs the shipping implementation: it returns before `tccutil` is ever started.
    @Test func anEmptyBundleIDNeverReachesTccutil() {
        #expect(!AccessibilityStatusModel.runTccutil(bundleID: ""))
    }
}

// MARK: - About Links & Export

/// The About tab's two outward jobs. Asserted on the model: the view is SwiftUI and has
/// no buttons to click, and `await model.exportLogs()` is a plain await rather than a
/// click followed by `waitUntil`.
@Suite("About links")
@MainActor
struct AboutLinkTests {

    @MainActor
    private final class Recorder {
        var log: String? = "collected log"
        var opened: [URL] = []
        var saved: [String] = []
    }

    private func makeModel(_ recorder: Recorder) -> AboutModel {
        let scratch = ScratchPreferences()
        let service = SmartDockService(
            displayMonitor: MockDisplayMonitor(), dockController: MockDockController(),
            prefs: scratch.prefs)
        return AboutModel(
            service: service, prefs: scratch.prefs,
            openURL: { recorder.opened.append($0) },
            collectLog: { await MainActor.run { recorder.log } },
            saveLog: { recorder.saved.append($0) },
            copyToPasteboard: { _ in },
            afterConfirmation: { _ in })
    }

    @Test func thelinkToTheRepositoryPointsAtIt() {
        let recorder = Recorder()

        makeModel(recorder).openRepository()

        #expect(recorder.opened.count == 1)
        #expect(recorder.opened.first?.absoluteString.contains("github.com") == true)
    }

    @Test func thelinkToTheChangelogPointsAtTheReleases() {
        let recorder = Recorder()

        makeModel(recorder).openReleases()

        #expect(recorder.opened.count == 1)
        #expect(recorder.opened.first?.absoluteString.contains("releases") == true)
    }

    /// The write behind the save panel: the panel needs a person, the write does not.
    @Test func theExportedLogIsWrittenToThePickedFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("smartdock-export-test.txt")
        defer { try? FileManager.default.removeItem(at: url) }

        AboutModel.write("two lines\nof log", to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == "two lines\nof log")
    }

    /// An unwritable destination is logged, not crashed on.
    @Test func anUnwritableDestinationIsSurvived() {
        AboutModel.write("x", to: URL(fileURLWithPath: "/no/such/dir/export.txt"))
    }

    /// The tab says what it is doing and stops saying it afterwards, so a slow log read
    /// does not look like a dead window.
    @Test func exportingCollectsThenOffersToSave() async {
        let recorder = Recorder()
        let model = makeModel(recorder)

        await model.exportLogs()

        #expect(recorder.saved == ["collected log"])
        #expect(!model.isCollectingLog)
    }

    /// Nothing to export: no empty file is offered, and the tab stops collecting.
    @Test func anEmptyLogIsNotOfferedForSaving() async {
        let recorder = Recorder()
        recorder.log = ""
        let model = makeModel(recorder)

        await model.exportLogs()

        #expect(recorder.saved.isEmpty)
        #expect(!model.isCollectingLog)
    }

    @Test func afailedCollectionIsNotOfferedEither() async {
        let recorder = Recorder()
        recorder.log = nil
        let model = makeModel(recorder)

        await model.exportLogs()

        #expect(recorder.saved.isEmpty)
        #expect(!model.isCollectingLog)
    }
}

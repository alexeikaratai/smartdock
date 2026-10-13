import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

/// The flow that runs after **Grant Access…** relaunched the app. None of it was reachable
/// from a test while it lived in `App.swift` — the executable is outside this bundle — and
/// that is how it shipped for two releases without ever asking macOS to list SmartDock,
/// leaving the pane open on a list with no row to switch on.
@Suite("Accessibility grant watcher")
@MainActor
struct AccessibilityGrantWatcherTests {

    @MainActor
    private final class Recorder {
        /// Every outward step in the order it happened, which is the point of two of
        /// these tests: the ask has to come before the pane.
        var steps: [String] = []
        var granted = false
        /// Work handed to the one-second delay, run by the test instead of by a clock.
        var pending: [@MainActor () -> Void] = []

        func drain(_ times: Int) {
            for _ in 0..<times {
                guard let next = pending.popLast() else { return }
                next()
            }
        }
    }

    private func makeWatcher(_ recorder: Recorder, prefs: UserPreferences)
        -> AccessibilityGrantWatcher
    {
        AccessibilityGrantWatcher(
            prefs: prefs,
            showSettings: { recorder.steps.append("settings") },
            promptForTrust: { recorder.steps.append("ask") },
            openURL: { recorder.steps.append("pane:\($0.absoluteString)") },
            isGranted: { recorder.granted },
            relaunch: { recorder.steps.append("relaunch") },
            afterOneSecond: { recorder.pending.append($0) })
    }

    /// An ordinary launch must not open windows or ask for anything.
    @Test func nothingHappensWithoutAPendingGrant() {
        let recorder = Recorder()
        let scratch = ScratchPreferences()

        makeWatcher(recorder, prefs: scratch.prefs).startIfPending()

        #expect(recorder.steps.isEmpty)
        #expect(recorder.pending.isEmpty, "and nothing is left waiting on a clock")
    }

    /// The ask is what puts SmartDock in the list, so it cannot come after the pane —
    /// opening the pane first shows a list the app is not in yet.
    @Test func theAskComesBeforeThePane() throws {
        let recorder = Recorder()
        let scratch = ScratchPreferences()
        scratch.prefs.pendingAccessibilityGrant = true

        makeWatcher(recorder, prefs: scratch.prefs).startIfPending()

        let ask = try #require(recorder.steps.firstIndex(of: "ask"))
        let pane = try #require(recorder.steps.firstIndex { $0.contains("Privacy_Accessibility") })

        #expect(ask < pane, "steps were \(recorder.steps)")
        #expect(recorder.steps.first == "settings", "the status should be on screen first")
    }

    @Test func aGrantClearsTheFlagAndRelaunches() {
        let recorder = Recorder()
        let scratch = ScratchPreferences()
        scratch.prefs.pendingAccessibilityGrant = true
        let watcher = makeWatcher(recorder, prefs: scratch.prefs)

        watcher.startIfPending()
        recorder.granted = true
        recorder.drain(1)

        #expect(recorder.steps.contains("relaunch"))
        #expect(!scratch.prefs.pendingAccessibilityGrant, "or every later launch reopens Settings")
    }

    /// Nothing is relaunched while the switch stays off, and the wait keeps its place.
    @Test func thewaitKeepsGoingWhileThePermissionIsWithheld() {
        let recorder = Recorder()
        let scratch = ScratchPreferences()
        scratch.prefs.pendingAccessibilityGrant = true
        let watcher = makeWatcher(recorder, prefs: scratch.prefs)

        watcher.startIfPending()
        recorder.drain(10)

        #expect(!recorder.steps.contains("relaunch"))
        #expect(scratch.prefs.pendingAccessibilityGrant)
        #expect(recorder.pending.count == 1, "exactly one try is outstanding, never a pile")
    }

    /// Five minutes and the flag is dropped. Without this a grant nobody intended to give
    /// would reopen Settings on every launch from then on.
    ///
    /// Drained **exactly** `attemptBudget` times, not one more: with slack the test could
    /// not tell a budget of 300 from one of 301, and a mutation that moved the boundary by
    /// one survived it. The last try is the one that gives up, so after 300 there is
    /// nothing left outstanding.
    @Test func thewaitGivesUpAfterExactlyItsBudget() {
        let recorder = Recorder()
        let scratch = ScratchPreferences()
        scratch.prefs.pendingAccessibilityGrant = true
        let watcher = makeWatcher(recorder, prefs: scratch.prefs)

        watcher.startIfPending()
        recorder.drain(AccessibilityGrantWatcher.attemptBudget)

        #expect(!scratch.prefs.pendingAccessibilityGrant)
        #expect(!recorder.steps.contains("relaunch"))
        #expect(
            recorder.pending.isEmpty,
            "\(recorder.pending.count) still outstanding — the wait runs past its budget")
    }

    /// The flag can be cleared by something else — another window, another launch. Going
    /// on would relaunch the app under someone who never asked for it.
    @Test func aflagClearedElsewhereStopsTheWait() {
        let recorder = Recorder()
        let scratch = ScratchPreferences()
        scratch.prefs.pendingAccessibilityGrant = true
        let watcher = makeWatcher(recorder, prefs: scratch.prefs)

        watcher.startIfPending()
        scratch.prefs.pendingAccessibilityGrant = false
        recorder.granted = true
        recorder.drain(5)

        #expect(!recorder.steps.contains("relaunch"))
        #expect(recorder.pending.isEmpty, "and nothing is left waiting")
    }
}

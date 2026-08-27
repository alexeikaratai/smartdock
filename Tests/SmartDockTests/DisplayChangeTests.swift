import AppKit
import Foundation
import Testing

@testable import SmartDockCore

/// Covers what `DisplayMonitor` does *after* CoreGraphics tells it something moved:
/// debouncing the burst of callbacks, and firing only when the count of attached
/// displays genuinely changed.
///
/// The C callback itself cannot be exercised — it is a function pointer CG invokes.
/// Everything it leads to can, now that the display count is injectable.
@Suite("Display change handling")
@MainActor
struct DisplayChangeTests {

    private let settle: TimeInterval = 0.05

    private func waitPastSettle(_ multiplier: Double = 6) async throws {
        try await Task.sleep(nanoseconds: UInt64(settle * multiplier * 1_000_000_000))
    }

    /// Lets a test change what the "hardware" reports between callbacks.
    private final class DisplayCount {
        var value: Int
        init(_ value: Int) { self.value = value }
    }

    private func makeMonitor(
        startingAt count: Int
    ) -> (displays: DisplayCount, monitor: DisplayMonitor, fired: () -> Int) {
        let displays = DisplayCount(count)
        let monitor = DisplayMonitor(
            settleDelay: settle,
            wakeDelay: settle,
            countExternalDisplays: { displays.value })

        let counter = DisplayCount(0)
        monitor.onConfigurationChanged = { counter.value += 1 }

        // `start()` snapshots the current count, which is what later changes are
        // compared against.
        monitor.start()

        return (displays, monitor, { counter.value })
    }

    // MARK: - Only Real Changes

    /// CG fires for far more than connect and disconnect. A callback that leaves
    /// the display count untouched must not re-apply anything — doing so during a
    /// Mission Control or fullscreen transition is what disturbs the Dock.
    @Test func aCallbackThatChangesNothingIsIgnored() async throws {
        let (_, monitor, fired) = makeMonitor(startingAt: 1)

        monitor.handleReconfiguration()
        try await waitPastSettle()

        #expect(fired() == 0)
        monitor.stop()
    }

    @Test func aConnectedDisplayIsReported() async throws {
        let (displays, monitor, fired) = makeMonitor(startingAt: 0)

        displays.value = 1
        monitor.handleReconfiguration()
        try await waitPastSettle()

        #expect(fired() == 1)
        monitor.stop()
    }

    @Test func aDisconnectedDisplayIsReported() async throws {
        let (displays, monitor, fired) = makeMonitor(startingAt: 2)

        displays.value = 0
        monitor.handleReconfiguration()
        try await waitPastSettle()

        #expect(fired() == 1)
        monitor.stop()
    }

    // MARK: - Debouncing

    /// One physical connect produces a burst of CG callbacks. They must collapse
    /// into a single check, or the Dock is reconfigured several times over.
    @Test func aBurstOfCallbacksProducesOneCheck() async throws {
        let (displays, monitor, fired) = makeMonitor(startingAt: 0)

        displays.value = 1
        for _ in 0..<5 {
            monitor.handleReconfiguration()
        }
        try await waitPastSettle()

        #expect(fired() == 1, "Five callbacks for one connect is still one connect")
        monitor.stop()
    }

    /// Debouncing means the hardware is asked **once** after the burst, not once
    /// per callback. Counting the reads is the only way to see that directly: the
    /// change filter downstream would hide repeated checks by reporting just one.
    @Test func aBurstAsksTheHardwareOnlyOnce() async throws {
        let displays = DisplayCount(0)
        let reads = DisplayCount(0)
        let monitor = DisplayMonitor(
            settleDelay: settle, wakeDelay: settle,
            countExternalDisplays: {
                reads.value += 1
                return displays.value
            })
        monitor.start()
        let readsAfterStart = reads.value

        displays.value = 1
        for _ in 0..<5 {
            monitor.handleReconfiguration()
        }
        try await waitPastSettle()

        #expect(
            reads.value - readsAfterStart == 1,
            "Five callbacks should collapse into a single check, not five")
        monitor.stop()
    }

    /// The count is read after the burst settles, not when the first callback
    /// arrives — CG reports transient values mid-transition.
    @Test func theCountIsReadAfterThingsSettleNotBefore() async throws {
        let (displays, monitor, fired) = makeMonitor(startingAt: 0)

        // A transient reading during the transition, corrected before the check runs.
        displays.value = 3
        monitor.handleReconfiguration()
        displays.value = 0
        monitor.handleReconfiguration()
        try await waitPastSettle()

        #expect(fired() == 0, "The settled count matches where we started — nothing changed")
        monitor.stop()
    }

    // MARK: - Wake

    @Test func wakeWithTheSameDisplaysChangesNothing() async throws {
        let (_, monitor, fired) = makeMonitor(startingAt: 1)

        monitor.forceRecheck()
        try await waitPastSettle()

        #expect(fired() == 0, "Poking the Dock after every wake would disrupt fullscreen")
        monitor.stop()
    }

    /// Unplugging while the lid is shut is the case this exists for: no CG callback
    /// arrives, and the change is only noticed on wake.
    @Test func wakeNoticesDisplaysThatChangedWhileAsleep() async throws {
        let (displays, monitor, fired) = makeMonitor(startingAt: 1)

        displays.value = 0
        monitor.forceRecheck()
        try await waitPastSettle()

        #expect(fired() == 1)
        monitor.stop()
    }

    /// The wake check deliberately keeps its own work item.
    ///
    /// A single stray callback would not show why: both handlers do the same thing,
    /// so whichever survives detects the change. The difference appears under a
    /// *stream* of CG callbacks — each one resets the settle timer, so a shared work
    /// item is cancelled again before it ever runs, and the state after wake is
    /// never re-checked at all.
    @Test func aStreamOfDisplayCallbacksCannotStarveTheWakeCheck() async throws {
        let (displays, monitor, fired) = makeMonitor(startingAt: 1)

        displays.value = 0
        monitor.forceRecheck()

        // Callbacks arriving faster than the settle delay, for longer than the wake
        // delay: the CG check never gets to run, the wake check should anyway.
        for _ in 0..<6 {
            monitor.handleReconfiguration()
            try await Task.sleep(nanoseconds: UInt64(settle * 0.4 * 1_000_000_000))
        }

        #expect(fired() >= 1, "The wake re-check must fire on its own timer")
        monitor.stop()
    }

    // MARK: - Stopped

    @Test func aStoppedMonitorReportsNothing() async throws {
        let (displays, monitor, fired) = makeMonitor(startingAt: 0)
        monitor.stop()

        displays.value = 2
        monitor.handleReconfiguration()
        try await waitPastSettle()

        #expect(fired() == 0)
    }
}

// MARK: - Wake Notification & Teardown

/// Separated from the main suite because these exercise lifecycle rather than
/// change detection.
@Suite("Display monitor lifecycle")
@MainActor
struct DisplayMonitorLifecycleTests {

    private let settle: TimeInterval = 0.05

    @Test func aWakeNotificationSchedulesARecheck() async throws {
        var count = 1
        let fired = Counter()
        let monitor = DisplayMonitor(
            settleDelay: settle, wakeDelay: settle, countExternalDisplays: { count })
        monitor.onConfigurationChanged = { fired.bump() }
        monitor.start()

        // Unplugged with the lid shut: no CG callback ever arrives, and the change
        // is only noticed because waking re-checks.
        count = 0
        monitor.handleWake(Notification(name: NSWorkspace.didWakeNotification))
        try await Task.sleep(nanoseconds: UInt64(settle * 6 * 1_000_000_000))

        #expect(fired.value == 1)
        monitor.stop()
    }

    /// Waking a monitor that was never started must do nothing — the observers are
    /// only registered while running, but the guard is what makes that safe.
    @Test func wakingAStoppedMonitorDoesNothing() async throws {
        var count = 1
        let fired = Counter()
        let monitor = DisplayMonitor(
            settleDelay: settle, wakeDelay: settle, countExternalDisplays: { count })
        monitor.onConfigurationChanged = { fired.bump() }

        count = 0
        monitor.handleWake(Notification(name: NSWorkspace.didWakeNotification))
        try await Task.sleep(nanoseconds: UInt64(settle * 6 * 1_000_000_000))

        #expect(fired.value == 0)
    }

    /// A monitor that goes out of scope while still running has to unregister
    /// itself. Leaving a CoreGraphics callback pointing at freed memory is the kind
    /// of bug that shows up as a crash somewhere else entirely.
    @Test func aRunningMonitorCleansUpWhenDeallocated() {
        do {
            let monitor = DisplayMonitor(countExternalDisplays: { 0 })
            monitor.start()
            // Deliberately no stop() — deinit has to handle it.
        }

        // Reaching here without a crash is the assertion; make it explicit.
        #expect(Bool(true), "Deallocating a running monitor must not crash")
    }

    /// Reference counter usable from an escaping closure.
    private final class Counter {
        private(set) var value = 0
        func bump() { value += 1 }
    }
}

// MARK: - CoreGraphics Callback

/// Covers the C function CoreGraphics calls directly.
///
/// It is the one piece that a real display connect would exercise and nothing else
/// does: it decides whether the event is worth reacting to, recovers the monitor
/// from an opaque pointer, and hops to the main queue. A mistake in any of those
/// means SmartDock simply never notices a monitor — with no error anywhere.
@Suite("CoreGraphics callback")
@MainActor
struct DisplayCallbackTests {

    private let settle: TimeInterval = 0.05

    private func makeMonitor(count: @escaping () -> Int) -> (DisplayMonitor, Counter) {
        let fired = Counter()
        let monitor = DisplayMonitor(
            settleDelay: settle, wakeDelay: settle, countExternalDisplays: count)
        monitor.onConfigurationChanged = { fired.bump() }
        monitor.start()
        return (monitor, fired)
    }

    private func waitPastSettle() async throws {
        try await Task.sleep(nanoseconds: UInt64(settle * 8 * 1_000_000_000))
    }

    @Test func aTopologyEventReachesTheMonitor() async throws {
        var count = 0
        let (monitor, fired) = makeMonitor(count: { count })

        count = 1
        displayReconfigurationCallback(
            0, .addFlag, Unmanaged.passUnretained(monitor).toOpaque())
        try await waitPastSettle()

        #expect(fired.value == 1, "A connect must travel from the C callback through to the app")
        monitor.stop()
    }

    /// Mission Control and fullscreen transitions arrive here constantly. Letting
    /// them through would re-apply the Dock mid-animation.
    @Test func layoutNoiseNeverReachesTheMonitor() async throws {
        var count = 0
        let (monitor, fired) = makeMonitor(count: { count })

        count = 1
        displayReconfigurationCallback(
            0, .desktopShapeChangedFlag, Unmanaged.passUnretained(monitor).toOpaque())
        try await waitPastSettle()

        #expect(fired.value == 0)
        monitor.stop()
    }

    /// CG reports each change twice — once as it begins, once on completion. Acting
    /// on the first would read the display list mid-reconfiguration.
    @Test func theBeginConfigurationPassIsSkipped() async throws {
        var count = 0
        let (monitor, fired) = makeMonitor(count: { count })

        count = 1
        displayReconfigurationCallback(
            0, [.beginConfigurationFlag, .addFlag], Unmanaged.passUnretained(monitor).toOpaque())
        try await waitPastSettle()

        #expect(fired.value == 0, "Only the completion pass counts")
        monitor.stop()
    }

    /// Defensive: CG hands back whatever pointer was registered. A nil one must not
    /// take the app down.
    @Test func aMissingContextPointerIsIgnored() {
        displayReconfigurationCallback(0, .addFlag, nil)

        #expect(Bool(true), "A nil context must not crash")
    }

    private final class Counter {
        private(set) var value = 0
        func bump() { value += 1 }
    }
}

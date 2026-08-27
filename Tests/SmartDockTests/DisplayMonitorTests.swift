import CoreGraphics
import Testing

@testable import SmartDockCore

@Suite("Display monitoring")
@MainActor
struct DisplayMonitorTests {

    // MARK: - Reconfiguration Flag Filtering

    /// Guards the raw values the filter relies on. `CGDisplayChangeSummaryFlags`
    /// has no documented stable ABI contract, so pin the four we depend on.
    @Test func topologyFlagRawValues() {
        #expect(CGDisplayChangeSummaryFlags.beginConfigurationFlag.rawValue == 0x1)
        #expect(CGDisplayChangeSummaryFlags.addFlag.rawValue == 0x10)
        #expect(CGDisplayChangeSummaryFlags.removeFlag.rawValue == 0x20)
        #expect(CGDisplayChangeSummaryFlags.enabledFlag.rawValue == 0x100)
        #expect(CGDisplayChangeSummaryFlags.disabledFlag.rawValue == 0x200)
    }

    /// A display arriving or leaving is the only thing worth re-applying for.
    @Test(
        "Reacts to a display arriving or leaving",
        arguments: [
            CGDisplayChangeSummaryFlags.addFlag, .removeFlag, .enabledFlag, .disabledFlag,
        ])
    func reactsToTopologyChanges(flag: CGDisplayChangeSummaryFlags) {
        #expect(shouldReactToDisplayChange(flag))
    }

    /// Everything that fires during Mission Control, fullscreen transitions,
    /// resolution changes and window rearranging — none of it changes how many
    /// displays are attached, so none of it should touch the Dock.
    @Test(
        "Ignores layout noise",
        arguments: [
            CGDisplayChangeSummaryFlags.desktopShapeChangedFlag, .setModeFlag,
            .movedFlag, .setMainFlag, .mirrorFlag, .unMirrorFlag, [],
        ])
    func ignoresNonTopologyChanges(flag: CGDisplayChangeSummaryFlags) {
        #expect(!shouldReactToDisplayChange(flag))
    }

    /// The begin-configuration pass is skipped even when it carries topology flags —
    /// we act on the completion callback that follows.
    @Test(arguments: [
        [CGDisplayChangeSummaryFlags.beginConfigurationFlag, .addFlag],
        [.beginConfigurationFlag, .removeFlag],
    ])
    func ignoresBeginConfigurationEvenWithTopologyFlags(flags: CGDisplayChangeSummaryFlags) {
        #expect(!shouldReactToDisplayChange(flags))
    }

    /// A real connect usually arrives bundled with layout noise — still a connect.
    @Test(arguments: [
        [CGDisplayChangeSummaryFlags.addFlag, .setModeFlag, .desktopShapeChangedFlag],
        [.removeFlag, .movedFlag],
    ])
    func reactsWhenTopologyFlagMixedWithNoise(flags: CGDisplayChangeSummaryFlags) {
        #expect(shouldReactToDisplayChange(flags))
    }

    // MARK: - Mock Behavior Validation

    @Test func mockDefaultsToNoExternal() {
        let monitor = MockDisplayMonitor()

        #expect(monitor.externalDisplayCount() == 0)
        #expect(!monitor.hasExternalDisplay())
    }

    @Test func mockReportsExternalCorrectly() {
        let monitor = MockDisplayMonitor()
        monitor.mockExternalCount = 2

        #expect(monitor.externalDisplayCount() == 2)
        #expect(monitor.hasExternalDisplay())
    }

    @Test func mockCallbackFiresOnSimulation() {
        let monitor = MockDisplayMonitor()
        var callbackFired = false
        monitor.onConfigurationChanged = { callbackFired = true }

        monitor.simulateDisplayChange(externalCount: 1)

        #expect(callbackFired)
        #expect(monitor.externalDisplayCount() == 1)
    }

    @Test func mockTracksStartStopCalls() {
        let monitor = MockDisplayMonitor()

        monitor.start()
        monitor.start()
        monitor.stop()

        #expect(monitor.startCallCount == 2)
        #expect(monitor.stopCallCount == 1)
    }

    // MARK: - Real DisplayMonitor (unit-safe checks)

    /// The real monitor talks to the window server, so only what is safe to call
    /// without a display attached is exercised here.
    @Test func realMonitorReturnsNonNegativeCount() {
        // In CI there may be no displays at all, but never a negative count.
        #expect(DisplayMonitor().externalDisplayCount() >= 0)
    }

    /// The two must never disagree — every profile decision in the app is made on
    /// `hasExternalDisplay`, while diagnostics report the count. One saying "no
    /// monitor" while the other counts two would be invisible until a bug report.
    @Test func hasExternalDisplayAgreesWithTheCount() {
        let monitor = DisplayMonitor()

        #expect(monitor.hasExternalDisplay() == (monitor.externalDisplayCount() > 0))
    }

    @Test func realMonitorStartStopDoesNotCrash() {
        let monitor = DisplayMonitor()

        monitor.start()
        monitor.stop()
        monitor.stop()  // Double stop must also be safe.
    }
}

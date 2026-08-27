import Testing

@testable import SmartDockCore

@Suite("Service orchestration")
@MainActor
struct SmartDockServiceTests {

    // MARK: - Fixture

    /// Everything one test needs, with its own preferences domain.
    ///
    /// Replaces the old `setUp`, which wiped every `com.smartdock.*` key out of
    /// `UserDefaults.standard` — safe only because the suite was forbidden from
    /// running in parallel. Each test now owns its store instead.
    @MainActor
    private struct Fixture {
        let scratch = ScratchPreferences()
        let monitor = MockDisplayMonitor()
        let dock = MockDockController()
        let delegate = MockServiceDelegate()
        let service: SmartDockService

        var prefs: UserPreferences { scratch.prefs }

        init(externalCount: Int = 0) {
            // The starting profiles every test assumes: Dock visible with a
            // monitor attached, hidden on the laptop screen alone.
            scratch.prefs.externalConfig = DockConfiguration(autohide: false)
            scratch.prefs.builtinConfig = DockConfiguration(autohide: true)
            scratch.prefs.syncFromSystemEnabled = true

            monitor.mockExternalCount = externalCount
            service = SmartDockService(
                displayMonitor: monitor, dockController: dock, prefs: scratch.prefs)
            service.delegate = delegate
        }
    }

    // MARK: - Forcing a Profile

    /// The regression this method exists for.
    ///
    /// `applyProfile` used to be "apply the config, then `refresh()`", and `refresh()`
    /// re-derives the profile from the displays — so forcing built-in while a monitor
    /// was connected applied it and undid it in the same call. Hotkeys, `smartdock://`
    /// URLs and AppleScript were all affected, and forcing is only ever useful in
    /// exactly this situation.
    @Test func forcingBuiltinSurvivesWhileAnExternalDisplayIsConnected() throws {
        let f = Fixture(externalCount: 1)
        f.service.start()
        #expect(!(try #require(f.dock.lastAppliedConfig).autohide), "external profile applies on start")

        f.service.applyProfile(external: false)

        #expect(
            try #require(f.dock.lastAppliedConfig).autohide,
            "Built-in profile was requested explicitly and must not be overridden by the display state")
        #expect(f.service.currentConfig.autohide, "currentConfig must reflect what is actually applied")
    }

    @Test func forcingExternalSurvivesWithNoExternalDisplay() throws {
        let f = Fixture(externalCount: 0)
        f.service.start()
        #expect(try #require(f.dock.lastAppliedConfig).autohide, "built-in profile applies on start")

        f.service.applyProfile(external: true)

        #expect(!(try #require(f.dock.lastAppliedConfig).autohide))
        #expect(!f.service.currentConfig.autohide)
    }

    /// Forcing overrides the display, it does not misreport it — the menu bar and
    /// diagnostics must still say what hardware is actually attached.
    @Test func forcingAProfileLeavesReportedDisplayStateAlone() {
        let f = Fixture(externalCount: 1)
        f.service.start()

        f.service.applyProfile(external: false)

        #expect(f.service.hasExternalDisplay, "A forced profile does not unplug the monitor")
    }

    /// The override is deliberately not permanent: the next display event hands
    /// control back to automatic behaviour.
    @Test func theNextDisplayChangeEndsTheOverride() throws {
        let f = Fixture(externalCount: 1)
        f.service.start()
        f.service.applyProfile(external: false)
        #expect(try #require(f.dock.lastAppliedConfig).autohide)

        f.monitor.simulateDisplayChange(externalCount: 2)

        #expect(
            !(try #require(f.dock.lastAppliedConfig).autohide),
            "A display change should resume automatic profile selection")
    }

    @Test func forcingAProfileDoesNothingWhileStopped() {
        let f = Fixture(externalCount: 1)
        let callsBefore = f.dock.applyCallCount

        f.service.applyProfile(external: false)

        #expect(f.dock.applyCallCount == callsBefore, "A stopped service must not touch the Dock")
    }

    /// Read live rather than cached: the diagnostic report states how many displays
    /// are attached *now*, while `hasExternalDisplay` is the state the current
    /// profile was chosen from. Reporting the cached one would make a bug report
    /// disagree with the machine it came from.
    @Test func theDisplayCountIsReportedLive() {
        let f = Fixture(externalCount: 2)

        #expect(f.service.externalDisplayCount == 2)

        f.monitor.mockExternalCount = 3
        #expect(f.service.externalDisplayCount == 3, "The count must not be a snapshot")
    }

    // MARK: - Start / Stop

    @Test func startBeginsMonitoring() {
        let f = Fixture()

        f.service.start()

        #expect(f.service.isEnabled)
        #expect(f.monitor.startCallCount == 1)
    }

    @Test func stopEndsMonitoring() {
        let f = Fixture()

        f.service.start()
        f.service.stop()

        #expect(!f.service.isEnabled)
        #expect(f.monitor.stopCallCount == 1)
    }

    @Test func doubleStartIsNoop() {
        let f = Fixture()

        f.service.start()
        f.service.start()

        #expect(f.monitor.startCallCount == 1)
    }

    @Test func doubleStopIsNoop() {
        let f = Fixture()

        f.service.start()
        f.service.stop()
        f.service.stop()

        #expect(f.monitor.stopCallCount == 1)
    }

    @Test func startBeginsObservingSystemChanges() {
        let f = Fixture()

        f.service.start()

        #expect(f.dock.startObservingCallCount == 1)
    }

    @Test func stopEndsObservingSystemChanges() {
        let f = Fixture()

        f.service.start()
        f.service.stop()

        #expect(f.dock.stopObservingCallCount == 1)
    }

    // MARK: - Display Change → Dock Config Applied

    @Test func startAppliesConfig() {
        let f = Fixture(externalCount: 0)

        f.service.start()

        #expect(f.dock.applyCallCount == 1, "Should apply config on start")
        #expect(f.dock.lastAppliedConfig != nil)
    }

    @Test func externalConnectedAppliesExternalConfig() {
        let f = Fixture(externalCount: 0)
        f.service.start()

        f.monitor.simulateDisplayChange(externalCount: 1)

        #expect(f.service.hasExternalDisplay)
        #expect(f.dock.applyCallCount == 2, "start + display change")
    }

    @Test func externalDisconnectedAppliesBuiltinConfig() {
        let f = Fixture(externalCount: 1)
        f.service.start()

        f.monitor.simulateDisplayChange(externalCount: 0)

        #expect(!f.service.hasExternalDisplay)
        #expect(f.dock.applyCallCount == 2)
    }

    @Test func multipleExternalsStillAppliesConfig() {
        let f = Fixture(externalCount: 0)
        f.service.start()

        f.monitor.simulateDisplayChange(externalCount: 3)

        #expect(f.service.hasExternalDisplay)
    }

    // MARK: - Delegate

    @Test func delegateNotifiedOnStart() {
        let f = Fixture(externalCount: 1)

        f.service.start()

        #expect(f.delegate.stateUpdates.count == 1)
        #expect(f.delegate.stateUpdates[0].hasExternal)
    }

    @Test func delegateNotifiedOnChange() {
        let f = Fixture(externalCount: 0)
        f.service.start()

        f.monitor.simulateDisplayChange(externalCount: 1)
        f.monitor.simulateDisplayChange(externalCount: 0)

        #expect(f.delegate.stateUpdates.count == 3)  // start + 2 changes
        #expect(!f.delegate.stateUpdates[0].hasExternal)
        #expect(f.delegate.stateUpdates[1].hasExternal)
        #expect(!f.delegate.stateUpdates[2].hasExternal)
    }

    // MARK: - Disabled State

    @Test func changesIgnoredWhenDisabled() {
        let f = Fixture(externalCount: 0)
        f.service.start()
        let callsAfterStart = f.dock.applyCallCount

        f.service.stop()
        f.monitor.simulateDisplayChange(externalCount: 1)

        #expect(
            f.dock.applyCallCount == callsAfterStart,
            "Dock should not be touched when service is disabled")
    }

    @Test func displayChangeIgnoredWhenDisabled() {
        let f = Fixture(externalCount: 1)
        f.service.start()
        let callsAfterStart = f.dock.applyCallCount

        f.service.stop()
        f.monitor.onConfigurationChanged?()

        #expect(
            f.dock.applyCallCount == callsAfterStart,
            "Display change should be ignored when service is disabled")
    }

    // MARK: - Refresh

    @Test func refreshReappliesConfig() {
        let f = Fixture(externalCount: 0)
        f.service.start()
        let callsBefore = f.dock.applyCallCount

        f.service.refresh()

        #expect(f.dock.applyCallCount == callsBefore + 1)
    }

    @Test func refreshAppliesCorrectConfig() throws {
        let f = Fixture(externalCount: 1)
        f.service.start()

        f.service.refresh()

        #expect(
            !(try #require(f.dock.lastAppliedConfig).autohide),
            "Refresh should apply current mode's config")
    }

    // MARK: - Config Correctness

    @Test func externalConfigHasAutohideOff() throws {
        let f = Fixture(externalCount: 1)

        f.service.start()

        #expect(
            !(try #require(f.dock.lastAppliedConfig).autohide),
            "External mode should have autohide=false (dock visible)")
    }

    @Test func builtinConfigHasAutohideOn() throws {
        let f = Fixture(externalCount: 0)

        f.service.start()

        #expect(
            try #require(f.dock.lastAppliedConfig).autohide,
            "Built-in mode should have autohide=true (dock hidden)")
    }

    @Test func disconnectSwitchesToBuiltinConfig() throws {
        let f = Fixture(externalCount: 1)
        f.service.start()
        #expect(!(try #require(f.dock.lastAppliedConfig).autohide))

        f.monitor.simulateDisplayChange(externalCount: 0)

        #expect(!f.service.hasExternalDisplay)
        #expect(
            try #require(f.dock.lastAppliedConfig).autohide,
            "After disconnect, should apply builtin config with autohide=true")
    }

    @Test func connectSwitchesToExternalConfig() throws {
        let f = Fixture(externalCount: 0)
        f.service.start()
        #expect(try #require(f.dock.lastAppliedConfig).autohide)

        f.monitor.simulateDisplayChange(externalCount: 1)

        #expect(f.service.hasExternalDisplay)
        #expect(
            !(try #require(f.dock.lastAppliedConfig).autohide),
            "After connect, should apply external config with autohide=false")
    }

    // MARK: - Display Change Re-apply

    @Test func displayChangeTriggersApply() {
        let f = Fixture(externalCount: 1)
        f.service.start()
        let callsAfterStart = f.dock.applyCallCount

        f.monitor.onConfigurationChanged?()

        #expect(f.dock.applyCallCount == callsAfterStart + 1, "Display change should trigger apply")
    }

    @Test func displayChangePreservesCorrectMode() throws {
        let f = Fixture(externalCount: 2)
        f.service.start()

        f.monitor.onConfigurationChanged?()

        #expect(f.service.hasExternalDisplay)
        #expect(
            !(try #require(f.dock.lastAppliedConfig).autohide),
            "Display change with external monitors should keep external config")
    }

    // MARK: - Rapid State Changes

    @Test func rapidConnectDisconnect() throws {
        let f = Fixture(externalCount: 0)
        f.service.start()

        f.monitor.simulateDisplayChange(externalCount: 1)
        f.monitor.simulateDisplayChange(externalCount: 0)
        f.monitor.simulateDisplayChange(externalCount: 2)
        f.monitor.simulateDisplayChange(externalCount: 0)

        #expect(!f.service.hasExternalDisplay)
        #expect(
            try #require(f.dock.lastAppliedConfig).autohide,
            "After rapid changes ending with no external, should be builtin config")
    }

    // MARK: - External Dock Change (System Sync)

    @Test func externalDockChangeUpdatesActiveProfile() {
        let f = Fixture(externalCount: 0)
        f.prefs.builtinConfig = DockConfiguration(autohide: true, position: .bottom)
        f.service.start()

        f.dock.simulateExternalDockChange(DockConfiguration(autohide: false, position: .left))

        #expect(
            f.prefs.builtinConfig.position == .left,
            "External change should update active (built-in) profile")
        #expect(!f.prefs.builtinConfig.autohide)
    }

    @Test func externalDockChangeUpdatesExternalProfile() {
        let f = Fixture(externalCount: 1)
        f.prefs.externalConfig = DockConfiguration(autohide: false, position: .bottom)
        f.service.start()

        f.dock.simulateExternalDockChange(DockConfiguration(autohide: true, position: .right))

        #expect(
            f.prefs.externalConfig.position == .right,
            "External change should update active (external) profile")
        #expect(f.prefs.externalConfig.autohide)
    }

    @Test func externalDockChangeIgnoredWhenDisabled() {
        let f = Fixture(externalCount: 0)
        f.prefs.builtinConfig = DockConfiguration(autohide: true, position: .bottom)
        f.service.start()
        f.service.stop()

        f.dock.simulateExternalDockChange(DockConfiguration(autohide: false, position: .left))

        #expect(
            f.prefs.builtinConfig.position == .bottom,
            "External change should be ignored when service is disabled")
    }

    @Test func externalDockChangeIgnoredWhenSyncDisabled() {
        let f = Fixture(externalCount: 0)
        f.prefs.builtinConfig = DockConfiguration(autohide: true, position: .bottom)
        f.prefs.syncFromSystemEnabled = false
        f.service.start()

        f.dock.simulateExternalDockChange(DockConfiguration(autohide: false, position: .left))

        #expect(
            f.prefs.builtinConfig.position == .bottom,
            "External change should be ignored when sync is disabled")
    }

    @Test func externalDockChangeNotifiesDelegate() {
        let f = Fixture(externalCount: 0)
        f.service.start()
        let countBefore = f.delegate.stateUpdates.count

        f.dock.simulateExternalDockChange(DockConfiguration(autohide: false, position: .left))

        #expect(
            f.delegate.stateUpdates.count == countBefore + 1,
            "External change should notify delegate")
    }
}

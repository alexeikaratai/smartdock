import Foundation
import Testing

@testable import SmartDockCore

/// Covers the KVO path that imports Dock changes made outside the app.
///
/// This is where the loop prevention lives: every change SmartDock itself writes
/// comes straight back through the same observer, and telling the two apart is the
/// whole job. Get it wrong one way and the app ignores the user's edits in System
/// Settings; get it wrong the other and it fights them in a loop. Until the
/// preferences domain became injectable this could only be exercised by editing the
/// developer's real Dock.
@Suite("System sync")
@MainActor
struct DockSystemSyncTests {

    /// Short enough to keep the suite fast, long enough to still batch.
    private let debounce: TimeInterval = 0.05

    /// For tests that expect *nothing* to arrive: a fixed window past the debounce.
    private func waitForDebounce() async throws {
        try await Task.sleep(nanoseconds: UInt64(debounce * 6 * 1_000_000_000))
    }

    /// For tests that expect a report: wait for it, not for the clock. The debounce
    /// fires on the main queue, and other suites — the view tests especially — keep
    /// the main thread busy for longer than any fixed wait can allow for. Then one
    /// more debounce window, so a second report would still be seen.
    private func waitForReport(in log: ChangeLog) async throws {
        try await waitUntil { !log.configs.isEmpty }
        try await waitForDebounce()
    }

    /// Collects configs reported as externally changed.
    private final class ChangeLog {
        private(set) var configs: [DockConfiguration] = []
        func record(_ config: DockConfiguration) { configs.append(config) }
    }

    private func makeSubject() -> (store: InMemoryDefaults, controller: DockController, log: ChangeLog) {
        let subject = makeSubjectWithGlobal()
        // The global store is dropped here, not discarded: the controller's own closure
        // holds it, so the second observer still has a domain to watch.
        return (subject.store, subject.controller, subject.log)
    }

    /// Both domains, for the tests that care which one a key lives in.
    private func makeSubjectWithGlobal() -> (
        store: InMemoryDefaults, global: InMemoryDefaults, controller: DockController,
        log: ChangeLog
    ) {
        let store = InMemoryDefaults()
        let global = InMemoryDefaults()
        let centre = InMemoryDefaults()
        let log = ChangeLog()
        let controller = DockController(
            openDomain: {
                switch $0 {
                case DockController.globalPreferencesDomain: global
                case DockController.controlCentreDomain: centre
                default: store
                }
            },
            verificationDelay: 0.01,
            externalChangeDebounce: debounce, runScript: { _ in true })
        controller.onExternalConfigChanged = { log.record($0) }
        // `centre` is held by the closure, so the option observer still has a domain.
        return (store, global, controller, log)
    }

    /// The same controller with the two timers in **production's order**: verification
    /// after the debounce, so the debounced check lands *inside* the window where the
    /// Dock is still settling.
    ///
    /// `makeSubject` above inverts that — 0.01s against 0.05s — to keep the suite fast,
    /// and an inverted fixture cannot reach the interleaving at all. Here the order is
    /// the thing under test, not the speed, so it is spelled out rather than inherited.
    ///
    /// What keeps the order honest under load is not a wide window but waiting on the
    /// verification *event* in each test — see `aHalfAppliedDockIsNotReportedAsAnExternalEdit`
    /// for the vacuous pass a fixed wait produced here, and how `llvm-cov` caught it
    /// while the suite stayed green.
    /// `settleWindows` is how many debounce windows verification waits — eight, so the
    /// debounced check at one window is comfortably first. It does not need to be wider
    /// than that: the tests wait on the verification *event*, so a busy queue delays
    /// both in order rather than running the clock out on either.
    private func makeSettlingSubject(settleWindows: Double = 8) -> (
        store: InMemoryDefaults, controller: DockController, log: ChangeLog
    ) {
        let store = InMemoryDefaults()
        let log = ChangeLog()
        let controller = DockController(
            openDomain: { _ in store },
            verificationDelay: debounce * settleWindows, externalChangeDebounce: debounce,
            runScript: { _ in true })
        controller.onExternalConfigChanged = { log.record($0) }
        return (store, controller, log)
    }

    /// Applies a config the Dock takes only half of — the position lands, auto-hide
    /// is refused, which is what the Dock does while an app is full screen.
    private func applyAndRefuseAutohide(_ controller: DockController, into store: InMemoryDefaults) {
        store.set(false, forKey: "autohide")
        controller.startObservingSystemChanges()
        controller.apply(DockConfiguration(autohide: true, position: .left))
        // Only the position reaches the domain. `autohide` stays false: the refusal.
        store.set("left", forKey: "orientation")
    }

    // MARK: - A Refusal Is Not An External Edit

    /// A half-applied Dock is not somebody else's edit.
    ///
    /// The echo test compares the Dock against what was *asked* for, so inside the
    /// verification window a property the Dock has not taken reads as an external
    /// change — and the service then wrote the whole half-applied state into the
    /// stored profile. Measured on 10 Nov: a disconnect while an app was full screen
    /// put `autohide=false` into the built-in profile 0.5s after the apply, and the
    /// three refreshes that followed each logged "unchanged — skipped", because the
    /// profile and the Dock now agreed. Only editing the profile by hand brought it
    /// back. Verification reports a refusal without storing it; this path must not
    /// run before it.
    @Test func aHalfAppliedDockIsNotReportedAsAnExternalEdit() async throws {
        let (store, controller, log) = makeSettlingSubject()

        applyAndRefuseAutohide(controller, into: store)
        // Wait for the *event*, not the clock. A fixed window was here first and made
        // the test vacuous under a full parallel suite: the wait ran out before the
        // busy main queue reached the debounced check, the test returned, the
        // controller went away, and the check then fired into a `nil` self — nothing
        // reported, nothing proven. `llvm-cov` is how that was caught, not the suite,
        // which was green either way: the guard's early return showed **zero** hits
        // across the whole run and two when this suite ran alone. Waiting on
        // verification keeps the controller alive, and the debounced check is due far
        // earlier, so it is guaranteed to have run by the time this returns.
        try await waitUntil { controller.lastApplyOutcome != nil }

        #expect(log.configs.isEmpty, "A refusal is reported by verification, never stored")
    }

    /// And not after verification either, whichever of the two lands first.
    ///
    /// This fixture keeps the inverted order, where verification runs first and the
    /// guard above cannot help. What does is verification reconciling the echo
    /// baseline to what the Dock holds: the refused property stops being a difference
    /// before the debounced check ever reads it. Without that the refusal is reported
    /// as an external edit and the profile is overwritten with it — the same bug, one
    /// timer ordering away.
    @Test func aRefusalIsNotReportedWhenVerificationLandsFirst() async throws {
        let (store, controller, log) = makeSubject()

        applyAndRefuseAutohide(controller, into: store)
        // Verification first here, so wait for it, then give the debounced check its
        // window — for the same reason as above, the controller has to outlive both.
        try await waitUntil { controller.lastApplyOutcome != nil }
        try await waitForDebounce()

        #expect(log.configs.isEmpty, "A property the Dock refused is not an external edit")
    }

    /// The guard stands down for a *pending* verification, not for ever: an edit that
    /// arrives once the dust has settled is still the user's and still reported.
    @Test func anEditAfterTheApplyHasSettledIsStillReported() async throws {
        // Only needs verification to finish, not to be outrun, so it waits a short one.
        let (store, controller, log) = makeSettlingSubject(settleWindows: 8)

        applyAndRefuseAutohide(controller, into: store)
        try await waitUntil { controller.lastApplyOutcome != nil }

        // Now someone really does change the Dock in System Settings.
        store.set(96, forKey: "tilesize")
        try await waitForReport(in: log)

        #expect(log.configs.count == 1, "A settled edit is the user's and must arrive")
        let reported = try #require(log.configs.first)
        expectClose(reported.iconSize, DockConfiguration.pixelsToScale(96))
    }

    // MARK: - Observing

    /// A store that cannot be opened is observed by nobody — and stopping an
    /// observer that never started must not touch a `nil` domain either.
    @Test func anUnopenableStoreIsNeverObserved() {
        let controller = DockController(openDomain: { _ in nil }, runScript: { _ in true })

        controller.startObservingSystemChanges()
        controller.stopObservingSystemChanges()
        controller.stopObservingSystemChanges()
    }

    /// The service can stop and drop the controller during the debounce window.
    /// The pending check then fires with no controller behind it and must do nothing.
    @Test func aPendingCheckThatOutlivesItsControllerDoesNothing() async throws {
        let store = InMemoryDefaults()
        let log = ChangeLog()
        var controller: DockController? = DockController(
            openDomain: { _ in store }, verificationDelay: 0.01,
            externalChangeDebounce: debounce, runScript: { _ in true })
        controller?.onExternalConfigChanged = { log.record($0) }
        controller?.startObservingSystemChanges()

        store.set(true, forKey: "autohide")
        // KVO hands the change to the main queue; let it schedule the debounced
        // check *before* the controller goes away, so the check itself outlives it.
        try await Task.sleep(nanoseconds: UInt64(debounce / 5 * 1_000_000_000))
        controller = nil
        try await waitForDebounce()

        #expect(log.configs.isEmpty, "Nothing is left to report to")
    }

    @Test func anEditMadeOutsideTheAppIsReported() async throws {
        let (store, controller, log) = makeSubject()
        controller.startObservingSystemChanges()

        // Someone changes the Dock in System Settings.
        store.set("right", forKey: "orientation")
        try await waitForReport(in: log)

        #expect(log.configs.count == 1, "An external edit should be reported exactly once")
        #expect(log.configs.first?.position == .right)
    }

    /// Every property has a key the observer must watch, in the domain that holds it.
    /// A key missing from the list would make System Settings edits to that property
    /// vanish silently — no error, no log — and the next apply would then push the
    /// profile's old value back, undoing an edit the person had just made. The switch
    /// is exhaustive: a new property does not compile here until it names its key, and
    /// it has to say which domain, since the menu bar is not in the Dock's.
    @Test(arguments: DockProperty.allCases)
    func anEditToEveryPropertyIsReported(property: DockProperty) async throws {
        let (store, global, controller, log) = makeSubjectWithGlobal()
        // The magnified size is invisible — and deliberately not compared — while
        // magnification is off, just as its slider is disabled in System Settings.
        store.set(true, forKey: "magnification")
        controller.startObservingSystemChanges()

        // Each value differs from what the domain reads as, so the change is not
        // filtered out as SmartDock's own echo.
        let edit: (domain: InMemoryDefaults, key: String, value: Any) =
            switch property {
            case .position: (store, "orientation", "left")
            case .autohide: (store, "autohide", true)
            case .iconSize: (store, "tilesize", 80)
            case .magnification: (store, "magnification", false)
            case .magnificationSize: (store, "largesize", 100)
            case .minimizeEffect: (store, "mineffect", "scale")
            case .animatesLaunch: (store, "launchanim", false)
            case .showsRecents: (store, "show-recents", false)
            case .showsIndicators: (store, "show-process-indicators", false)
            case .minimizesToApplication: (store, "minimize-to-application", true)
            case .menuBarAutoHide: (global, "_HIHideMenuBar", true)
            case .doubleClickBehavior:
                (global, DockController.doubleClickKey, DoubleClickBehavior.minimize.systemValue)
            }
        edit.domain.set(edit.value, forKey: edit.key)
        try await waitForReport(in: log)

        #expect(log.configs.count == 1, "`\(edit.key)` is not observed")
    }

    /// The loop guard. SmartDock's own writes echo back through KVO; reporting
    /// them as external edits would have the app chasing its own tail.
    @Test func ourOwnChangeIsNotReportedBack() async throws {
        let (store, controller, log) = makeSubject()
        store.set("bottom", forKey: "orientation")
        controller.startObservingSystemChanges()

        // Apply through the controller, then let the domain reflect it the way the
        // Dock would have.
        controller.apply(DockConfiguration(position: .left))
        store.set("left", forKey: "orientation")
        try await waitForDebounce()

        #expect(log.configs.isEmpty, "A change we made ourselves is not an external edit")
    }

    /// System Settings writes several keys for one user action. Reporting each
    /// separately would overwrite the active profile several times over.
    @Test func severalKeysChangedTogetherAreReportedOnce() async throws {
        let (store, controller, log) = makeSubject()
        controller.startObservingSystemChanges()

        store.set("right", forKey: "orientation")
        store.set(true, forKey: "autohide")
        store.set(96, forKey: "tilesize")
        try await waitForReport(in: log)

        #expect(log.configs.count == 1, "One user action, one report")
        #expect(log.configs.first?.position == .right)
        #expect(log.configs.first?.autohide == true)
    }

    @Test func changesAfterStoppingAreIgnored() async throws {
        let (store, controller, log) = makeSubject()
        controller.startObservingSystemChanges()

        controller.stopObservingSystemChanges()
        store.set("right", forKey: "orientation")
        try await waitForDebounce()

        #expect(log.configs.isEmpty, "A stopped observer must not report anything")
    }

    @Test func nothingIsReportedBeforeObservingStarts() async throws {
        let (store, _, log) = makeSubject()

        store.set("right", forKey: "orientation")
        try await waitForDebounce()

        #expect(log.configs.isEmpty)
    }

    /// Starting twice must not leave two observers behind — the second start
    /// tears the first down, or every edit would arrive in duplicate.
    @Test func startingTwiceDoesNotDoubleReport() async throws {
        let (store, controller, log) = makeSubject()

        controller.startObservingSystemChanges()
        controller.startObservingSystemChanges()
        store.set("right", forKey: "orientation")
        try await waitForReport(in: log)

        #expect(log.configs.count == 1, "Two observers would report the same edit twice")
    }
}

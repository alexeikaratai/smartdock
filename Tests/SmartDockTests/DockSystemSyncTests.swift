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
        let store = InMemoryDefaults()
        let log = ChangeLog()
        let controller = DockController(
            openDefaults: { store }, verificationDelay: 0.01,
            externalChangeDebounce: debounce, runScript: { _ in true })
        controller.onExternalConfigChanged = { log.record($0) }
        return (store, controller, log)
    }

    // MARK: - Observing

    /// A store that cannot be opened is observed by nobody — and stopping an
    /// observer that never started must not touch a `nil` domain either.
    @Test func anUnopenableStoreIsNeverObserved() {
        let controller = DockController(openDefaults: { nil }, runScript: { _ in true })

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
            openDefaults: { store }, verificationDelay: 0.01,
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

    /// Every property has a key the observer must watch. A key missing from the
    /// list would make System Settings edits to that property vanish silently — no
    /// error, no log — which is exactly what happened to nothing only because the
    /// list was extended by hand each time. The switch is exhaustive: a new property
    /// does not compile here until it names its key.
    @Test(arguments: DockProperty.allCases)
    func anEditToEveryPropertyIsReported(property: DockProperty) async throws {
        let (store, controller, log) = makeSubject()
        // The magnified size is invisible — and deliberately not compared — while
        // magnification is off, just as its slider is disabled in System Settings.
        store.set(true, forKey: "magnification")
        controller.startObservingSystemChanges()

        // Each value differs from what the domain reads as, so the change is not
        // filtered out as SmartDock's own echo.
        let edit: (key: String, value: Any) =
            switch property {
            case .position: ("orientation", "left")
            case .autohide: ("autohide", true)
            case .iconSize: ("tilesize", 80)
            case .magnification: ("magnification", false)
            case .magnificationSize: ("largesize", 100)
            case .minimizeEffect: ("mineffect", "scale")
            case .animatesLaunch: ("launchanim", false)
            case .showsRecents: ("show-recents", false)
            case .showsIndicators: ("show-process-indicators", false)
            case .minimizesToApplication: ("minimize-to-application", true)
            }
        store.set(edit.value, forKey: edit.key)
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

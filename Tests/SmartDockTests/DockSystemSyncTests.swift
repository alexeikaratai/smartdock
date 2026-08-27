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

    private func waitForDebounce() async throws {
        try await Task.sleep(nanoseconds: UInt64(debounce * 6 * 1_000_000_000))
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

    @Test func anEditMadeOutsideTheAppIsReported() async throws {
        let (store, controller, log) = makeSubject()
        controller.startObservingSystemChanges()

        // Someone changes the Dock in System Settings.
        store.set("right", forKey: "orientation")
        try await waitForDebounce()

        #expect(log.configs.count == 1, "An external edit should be reported exactly once")
        #expect(log.configs.first?.position == .right)
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
        try await waitForDebounce()

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
        try await waitForDebounce()

        #expect(log.configs.count == 1, "Two observers would report the same edit twice")
    }
}

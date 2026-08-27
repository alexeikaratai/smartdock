import Testing

@testable import SmartDockCore

/// Guards the fix for a launch-time crash: a `smartdock://` URL or an Apple Event
/// can start the app, and the command arrives before the managers that run it
/// exist. This logic used to sit in `AppDelegate`, where no test could reach it.
@Suite("Pending command queue")
struct PendingCommandQueueTests {

    // MARK: - During Launch

    @Test func commandsAreHeldWhileStartingUp() {
        var queue = PendingCommandQueue()

        let ready = queue.submit(.refresh)

        #expect(!queue.isReady)
        #expect(ready.isEmpty, "Nothing may run before the app is ready")
        #expect(queue.pendingCount == 1)
    }

    /// The point of the whole type: the command the user issued must survive
    /// launch rather than being dropped or crashing on a nil manager.
    @Test func heldCommandsAreReleasedOnceReady() {
        var queue = PendingCommandQueue()

        _ = queue.submit(.refresh)
        _ = queue.submit(.switchToExternal)
        let drained = queue.markReady()

        #expect(drained == [.refresh, .switchToExternal])
    }

    /// `open smartdock://a smartdock://b` must not run b before a.
    @Test func orderIsPreserved() {
        var queue = PendingCommandQueue()

        for command in [URLCommand.openSettings, .toggleAutohide, .refresh, .switchToBuiltin] {
            _ = queue.submit(command)
        }
        let drained = queue.markReady()

        #expect(drained == [.openSettings, .toggleAutohide, .refresh, .switchToBuiltin])
    }

    // MARK: - After Launch

    @Test func commandsRunImmediatelyOnceReady() {
        var queue = PendingCommandQueue()
        _ = queue.markReady()

        let ready = queue.submit(.refresh)

        #expect(queue.isReady)
        #expect(ready == [.refresh])
        #expect(queue.pendingCount == 0, "A command that ran must not also be queued")
    }

    /// Draining twice would run every queued command a second time — a `refresh`
    /// is harmless, but `switch to builtin` twice is a visible dock flicker.
    @Test func drainingTwiceYieldsNothingTheSecondTime() {
        var queue = PendingCommandQueue()
        _ = queue.submit(.refresh)

        let first = queue.markReady()
        let second = queue.markReady()

        #expect(first == [.refresh])
        #expect(second.isEmpty)
    }

    @Test func readyQueueWithNothingHeldDrainsEmpty() {
        var queue = PendingCommandQueue()

        let drained = queue.markReady()

        #expect(drained.isEmpty)
    }
}

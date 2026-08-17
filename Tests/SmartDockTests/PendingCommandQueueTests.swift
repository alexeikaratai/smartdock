import XCTest

@testable import SmartDockCore

/// Guards the fix for a launch-time crash: a `smartdock://` URL or an Apple Event
/// can start the app, and the command arrives before the managers that run it
/// exist. This logic used to sit in `AppDelegate`, where no test could reach it.
final class PendingCommandQueueTests: XCTestCase {

    // MARK: - During Launch

    func testCommandsAreHeldWhileStartingUp() {
        var queue = PendingCommandQueue()

        XCTAssertFalse(queue.isReady)
        XCTAssertTrue(queue.submit(.refresh).isEmpty, "Nothing may run before the app is ready")
        XCTAssertEqual(queue.pendingCount, 1)
    }

    /// The point of the whole type: the command the user issued must survive
    /// launch rather than being dropped or crashing on a nil manager.
    func testHeldCommandsAreReleasedOnceReady() {
        var queue = PendingCommandQueue()

        _ = queue.submit(.refresh)
        _ = queue.submit(.switchToExternal)

        XCTAssertEqual(queue.markReady(), [.refresh, .switchToExternal])
    }

    /// `open smartdock://a smartdock://b` must not run b before a.
    func testOrderIsPreserved() {
        var queue = PendingCommandQueue()

        for command in [URLCommand.openSettings, .toggleAutohide, .refresh, .switchToBuiltin] {
            _ = queue.submit(command)
        }

        XCTAssertEqual(queue.markReady(), [.openSettings, .toggleAutohide, .refresh, .switchToBuiltin])
    }

    // MARK: - After Launch

    func testCommandsRunImmediatelyOnceReady() {
        var queue = PendingCommandQueue()
        _ = queue.markReady()

        XCTAssertTrue(queue.isReady)
        XCTAssertEqual(queue.submit(.refresh), [.refresh])
        XCTAssertEqual(queue.pendingCount, 0, "A command that ran must not also be queued")
    }

    /// Draining twice would run every queued command a second time — a `refresh`
    /// is harmless, but `switch to builtin` twice is a visible dock flicker.
    func testDrainingTwiceYieldsNothingTheSecondTime() {
        var queue = PendingCommandQueue()
        _ = queue.submit(.refresh)

        XCTAssertEqual(queue.markReady(), [.refresh])
        XCTAssertTrue(queue.markReady().isEmpty)
    }

    func testReadyQueueWithNothingHeldDrainsEmpty() {
        var queue = PendingCommandQueue()
        XCTAssertTrue(queue.markReady().isEmpty)
    }
}

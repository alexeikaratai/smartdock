import Foundation

// MARK: - Pending Command Queue

/// Holds commands that arrive before the app is ready to run them.
///
/// Both a `smartdock://` URL and an Apple Event can *launch* SmartDock, and the
/// event is delivered before `applicationDidFinishLaunching` has built the
/// managers that execute it. Running one then would dereference a nil manager;
/// dropping it would silently lose the command the user just issued. So it waits.
///
/// Lives in Core because the alternative — leaving it inline in `AppDelegate` —
/// puts the fix for a launch-time crash in the one target that has no tests.
public struct PendingCommandQueue: Sendable {

    /// Whether the app has finished starting up and can execute commands.
    public private(set) var isReady = false

    private var queued: [URLCommand] = []

    public init() {}

    /// Commands to run right now for this submission.
    ///
    /// Returns the command itself once the app is ready, or nothing while it is
    /// still starting up — in which case the command is held for `markReady`.
    public mutating func submit(_ command: URLCommand) -> [URLCommand] {
        guard isReady else {
            queued.append(command)
            return []
        }
        return [command]
    }

    /// Marks the app ready and hands back everything held during startup, in the
    /// order it arrived. Subsequent calls return nothing — a queue can only be
    /// drained once, or a command would run twice.
    public mutating func markReady() -> [URLCommand] {
        isReady = true

        let drained = queued
        queued.removeAll()
        return drained
    }

    /// How many commands are waiting. For logging.
    public var pendingCount: Int {
        queued.count
    }
}

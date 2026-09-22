import Cocoa
import SmartDockCore

/// Handles app relaunch — waits for current process to exit before
/// opening a new instance, preventing parallel instances during update or reset.
@MainActor
public enum AppRelauncher {

    /// What a relaunch asks the system to run. Built here so a test can read it
    /// back without spawning anything.
    struct Plan: Equatable {
        let executable: String
        let arguments: [String]
        let environment: [String: String]
    }

    /// Waits up to 5s (50 × 0.1s) for `pid` to exit, then opens a new instance.
    /// The path travels in an env var rather than the script text, so quotes and
    /// spaces in it cannot become shell syntax.
    static func plan(bundlePath: String, pid: Int32) -> Plan {
        let script = """
            i=0
            while [ $i -lt 50 ] && kill -0 \(pid) 2>/dev/null; do
                sleep 0.1
                i=$((i+1))
            done
            /usr/bin/open -n "$BUNDLE_PATH"
            """
        return Plan(
            executable: "/bin/sh", arguments: ["-c", script],
            environment: ["BUNDLE_PATH": bundlePath])
    }

    /// Runs a plan by spawning a process — the one step a test never takes.
    static func spawn(_ plan: Plan) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: plan.executable)
        task.arguments = plan.arguments
        task.environment = plan.environment
        try task.run()
    }

    /// Relaunch the app at the given bundle path. `run` and `terminate` are
    /// parameters because a test can neither spawn a shell nor quit the runner.
    public static func relaunch(bundlePath: String) {
        relaunch(bundlePath: bundlePath, run: spawn, terminate: { NSApp.terminate(nil) })
    }

    static func relaunch(
        bundlePath: String,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        run: (Plan) throws -> Void,
        terminate: () -> Void
    ) {
        do {
            try run(plan(bundlePath: bundlePath, pid: pid))
            Log.info("Relaunch scheduled — waiting for PID \(pid) to exit")
            terminate()
        } catch {
            // Spawn failed — don't terminate, keep the app running.
            Log.error("Failed to schedule relaunch: \(error)")
        }
    }
}

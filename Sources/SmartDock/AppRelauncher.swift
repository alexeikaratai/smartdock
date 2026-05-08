import Cocoa
import SmartDockCore

/// Handles app relaunch — waits for current process to exit before
/// opening a new instance, preventing parallel instances during update or reset.
@MainActor
enum AppRelauncher {

    /// Relaunch the app at the given bundle path.
    /// Spawns a shell that waits up to 5s for the current PID to exit, then
    /// opens a new instance. Path is passed via env var to avoid shell injection.
    static func relaunch(bundlePath: String) {
        let pid = ProcessInfo.processInfo.processIdentifier

        // Wait for PID with bounded timeout (50 × 0.1s = 5s).
        // Uses env var for path so quotes/spaces in path are safe.
        let script = """
            i=0
            while [ $i -lt 50 ] && kill -0 \(pid) 2>/dev/null; do
                sleep 0.1
                i=$((i+1))
            done
            /usr/bin/open -n "$BUNDLE_PATH"
            """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        task.environment = ["BUNDLE_PATH": bundlePath]
        do {
            try task.run()
            Log.info("Relaunch scheduled — waiting for PID \(pid) to exit")
            NSApp.terminate(nil)
        } catch {
            // Spawn failed — don't terminate, keep the app running.
            Log.error("Failed to schedule relaunch: \(error)")
        }
    }
}

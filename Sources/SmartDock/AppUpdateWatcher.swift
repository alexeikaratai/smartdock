import Cocoa
import SmartDockCore

/// Watches the app's executable for changes (e.g. Homebrew upgrade replaces it).
/// When detected, prompts user to relaunch the new version.
@MainActor
final class AppUpdateWatcher {

    /// Accessed from deinit (nonisolated) — must be nonisolated(unsafe).
    private nonisolated(unsafe) var source: DispatchSourceFileSystemObject?
    private var pendingPrompt: DispatchWorkItem?
    private var hasPrompted = false

    func start() {
        guard source == nil else { return } // idempotent
        guard let path = Bundle.main.executablePath else { return }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            Log.error("AppUpdateWatcher: failed to open \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.delete, .write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
        Log.info("AppUpdateWatcher started on \(path)")
    }

    func stop() {
        source?.cancel()
        source = nil
        pendingPrompt?.cancel()
        pendingPrompt = nil
    }

    deinit {
        source?.cancel()
    }

    // MARK: - Private

    private func handleChange() {
        guard !hasPrompted else { return }

        // Debounce — Homebrew may write multiple times during install
        pendingPrompt?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPrompt = nil
            self.promptForRelaunch()
        }
        pendingPrompt = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func promptForRelaunch() {
        guard !hasPrompted else { return }
        hasPrompted = true

        // FD is invalid after binary deletion — stop watching to free resources.
        // Won't re-prompt within this session; user can manually relaunch later.
        source?.cancel()
        source = nil

        Log.info("App binary changed — prompting for relaunch")

        let alert = NSAlert()
        alert.messageText = "SmartDock was updated"
        alert.informativeText = "A new version was installed. Relaunch to use it?"
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            AppRelauncher.relaunch(bundlePath: Bundle.main.bundlePath)
        }
    }
}

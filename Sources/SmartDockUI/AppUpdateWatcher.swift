import Cocoa
import SmartDockCore

/// Watches the app's executable for changes (e.g. Homebrew upgrade replaces it).
/// When detected, prompts user to relaunch the new version.
@MainActor
public final class AppUpdateWatcher {

    /// Accessed from deinit (nonisolated) — must be nonisolated(unsafe).
    private nonisolated(unsafe) var source: (any DispatchSourceFileSystemObject)?
    private var pendingPrompt: DispatchWorkItem?
    private(set) var hasPrompted = false

    /// What is watched, how long the writes are allowed to settle, and what happens
    /// once they have. The app watches its own executable, waits 2s and shows an
    /// alert; a test watches a file it can touch, waits milliseconds, and answers
    /// the question itself.
    private let executablePath: () -> String?
    private let debounce: TimeInterval
    private let ask: () -> Bool
    private let relaunch: () -> Void

    // MARK: - Init

    public convenience init() {
        self.init(
            executablePath: { Bundle.main.executablePath },
            ask: AppUpdateWatcher.askWithAlert,
            relaunch: { AppRelauncher.relaunch(bundlePath: Bundle.main.bundlePath) })
    }

    init(
        executablePath: @escaping () -> String?,
        debounce: TimeInterval = 2.0,
        ask: @escaping () -> Bool,
        relaunch: @escaping () -> Void
    ) {
        self.executablePath = executablePath
        self.debounce = debounce
        self.ask = ask
        self.relaunch = relaunch
    }

    /// The app's question: a modal alert.
    static func askWithAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "SmartDock was updated"
        alert.informativeText = "A new version was installed. Relaunch to use it?"
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational
        return alert.runModal() == .alertFirstButtonReturn
    }

    public func start() {
        guard source == nil else { return }  // idempotent
        guard let path = executablePath() else { return }

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

    public func stop() {
        source?.cancel()
        source = nil
        pendingPrompt?.cancel()
        pendingPrompt = nil
    }

    deinit {
        source?.cancel()
    }

    // MARK: - Private

    /// Internal so a test can stand in for the file-system event.
    func handleChange() {
        guard !hasPrompted else { return }

        // Debounce — Homebrew may write multiple times during install
        pendingPrompt?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPrompt = nil
            self.promptForRelaunch()
        }
        pendingPrompt = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func promptForRelaunch() {
        guard !hasPrompted else { return }
        hasPrompted = true

        // FD is invalid after binary deletion — stop watching to free resources.
        // Won't re-prompt within this session; user can manually relaunch later.
        source?.cancel()
        source = nil

        Log.info("App binary changed — prompting for relaunch")

        if ask() { relaunch() }
    }
}

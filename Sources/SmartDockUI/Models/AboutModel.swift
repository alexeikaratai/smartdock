import AppKit
import Observation
import SmartDockCore
import UniformTypeIdentifiers

// MARK: - About Model

/// What the About tab shows and does: app identity, two links, and the two things a bug
/// report needs — a diagnostic snapshot on the clipboard and the app's own log in a file.
///
/// **Copy Diagnostic Info** says what the settings are, **Export Logs** says what actually
/// happened, including whether the Dock honoured each change.
///
/// Everything that leaves the process is a parameter: opening a browser, spawning
/// `log show`, putting up a save panel, and — new here — writing the pasteboard. The last
/// one used to be `NSPasteboard.general` inline, so the tests ate whatever the developer
/// had copied. The confirmation delay is a parameter for the same kind of reason: a test
/// that waits 1.5s to watch a button go back to its invitation is a test that costs 1.5s.
@MainActor
@Observable
final class AboutModel {

    /// True while the button says "Copied ✓" rather than inviting a copy. Temporary, or a
    /// second bug report gets filed from a button that still claims the first was copied.
    private(set) var hasCopied = false
    private(set) var isCollectingLog = false

    let appVersion: String

    @ObservationIgnored private let service: SmartDockService
    @ObservationIgnored private let prefs: UserPreferences
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    @ObservationIgnored private let collectLog: @Sendable () async -> String?
    @ObservationIgnored private let saveLog: @MainActor (String) -> Void
    @ObservationIgnored private let copyToPasteboard: @MainActor (String) -> Void
    @ObservationIgnored private let afterConfirmation: @MainActor (@escaping @MainActor () -> Void) -> Void

    static let repoURL = "https://github.com/alexeikaratai/smartdock"
    static let releasesURL = "https://github.com/alexeikaratai/smartdock/releases"

    // MARK: - Init

    init(
        service: SmartDockService,
        prefs: UserPreferences = .shared,
        appVersion: String = Bundle.main.shortVersion,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        collectLog: @escaping @Sendable () async -> String? = AboutModel.runLogShow,
        saveLog: @escaping @MainActor (String) -> Void = AboutModel.presentSavePanel,
        copyToPasteboard: @escaping @MainActor (String) -> Void = AboutModel.writeToGeneralPasteboard,
        afterConfirmation: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated(work) }
        }
    ) {
        self.service = service
        self.prefs = prefs
        self.appVersion = appVersion
        self.openURL = openURL
        self.collectLog = collectLog
        self.saveLog = saveLog
        self.copyToPasteboard = copyToPasteboard
        self.afterConfirmation = afterConfirmation
    }

    // MARK: - Intents

    func openRepository() {
        guard let url = URL(string: Self.repoURL) else { return }
        openURL(url)
    }

    func openReleases() {
        guard let url = URL(string: Self.releasesURL) else { return }
        openURL(url)
    }

    /// Confirms in place — a modal for a clipboard write would be heavy-handed.
    func copyDiagnostics() {
        copyToPasteboard(makeReport().formatted)
        hasCopied = true
        Log.info("Diagnostic info copied to clipboard")

        afterConfirmation { [weak self] in
            self?.hasCopied = false
        }
    }

    /// Collects off the main thread — `log show` reads a system store and can take a few
    /// seconds, which would freeze the window if done inline. Nothing is offered for
    /// saving when the collection came back empty or failed: a save panel over no log
    /// wastes the person's time twice.
    func exportLogs() async {
        isCollectingLog = true
        let text = await collectLog()
        isCollectingLog = false

        guard let text, !text.isEmpty else {
            Log.error("Log export produced nothing")
            NSSound.beep()
            return
        }
        saveLog(text)
    }

    // MARK: - System seams

    /// The app's real pasteboard write. A parameter above, because a test that used this
    /// would replace whatever the person running it had on their clipboard.
    static func writeToGeneralPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Runs `log show` off the main thread.
    static func runLogShow() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: LogExport.toolPath)
                process.arguments = LogExport.arguments(lastHours: 24)

                let output = Pipe()
                process.standardOutput = output
                process.standardError = Pipe()

                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let raw = String(data: data, encoding: .utf8) ?? ""
                    // Strip the account name out of logged bundle paths before this ever
                    // reaches an issue tracker.
                    continuation.resume(
                        returning: LogExport.redacting(raw, homeDirectory: NSHomeDirectory()))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Asks where to write, then writes. A parameter because a save panel waits for a
    /// person.
    static func presentSavePanel(for text: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = LogExport.defaultFileName(at: Date())
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { Self.write(text, to: url) }
        }
    }

    /// The write itself, separate from the panel that chooses where — the panel needs a
    /// person, the write does not.
    static func write(_ text: String, to url: URL) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            Log.info("Exported log to \(url.lastPathComponent)")
        } catch {
            Log.error("Failed to write exported log: \(error)")
            NSSound.beep()
        }
    }

    // MARK: - Private

    private func makeReport() -> DiagnosticReport {
        let info = Bundle.main.infoDictionary

        return DiagnosticReport(
            appVersion: appVersion,
            buildNumber: info?["CFBundleVersion"] as? String ?? "?",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            isAccessibilityGranted: AccessibilityChecker.isGranted,
            externalDisplayCount: service.externalDisplayCount,
            hasExternalDisplay: service.hasExternalDisplay,
            activeProfile: service.activeProfile,
            externalConfig: prefs.externalConfig,
            builtinConfig: prefs.builtinConfig,
            notificationsEnabled: prefs.notificationsEnabled,
            syncFromSystemEnabled: prefs.syncFromSystemEnabled,
            hotkeys: HotkeyAction.allCases.map { action in
                DiagnosticReport.Hotkey(
                    action: action.displayName,
                    shortcut: prefs.hotkey(for: action.rawValue)?.displayString
                )
            },
            lastApplyOutcome: service.dockController.lastApplyOutcome
        )
    }
}

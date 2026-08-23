import Cocoa
import SmartDockCore
import UniformTypeIdentifiers

// MARK: - About Tab

/// Contents of the Settings window's About tab: app identity, links, and a
/// one-click diagnostic dump for bug reports.
@MainActor
final class AboutTabView: NSView {

    private static let repoURL = "https://github.com/alexeikaratai/smartdock"
    private static let releasesURL = "https://github.com/alexeikaratai/smartdock/releases"

    private let service: SmartDockService
    private var copyButton: NSButton!
    private var exportButton: NSButton!
    private var copyResetWork: DispatchWorkItem?

    // MARK: - Init

    init(service: SmartDockService) {
        self.service = service
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("AboutTabView is built programmatically — init(coder:) is unavailable")
    }

    // MARK: - Private

    private func buildUI() {
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 36, weight: .light)
        if let icon = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "SmartDock") {
            iconView.image = icon.withSymbolConfiguration(iconConfig)
            iconView.contentTintColor = .controlAccentColor
        }
        addSubview(iconView)

        let nameLabel = UI.label("SmartDock", font: .systemFont(ofSize: 18, weight: .semibold))
        nameLabel.alignment = .center
        addSubview(nameLabel)

        let versionLabel = UI.label(
            "v\(Bundle.main.shortVersion) · by Alex Karatai",
            font: .systemFont(ofSize: 11))
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center
        addSubview(versionLabel)

        let descLabel = UI.label(
            "Automatically adjusts Dock settings for your display setup.",
            font: .systemFont(ofSize: 12)
        )
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 0
        descLabel.lineBreakMode = .byWordWrapping
        addSubview(descLabel)

        let githubButton = UI.smallButton("GitHub", target: self, action: #selector(openGitHub))
        addSubview(githubButton)

        let changelogButton = UI.smallButton("Changelog", target: self, action: #selector(openChangelog))
        addSubview(changelogButton)

        copyButton = UI.smallButton("Copy Diagnostic Info", target: self, action: #selector(copyDiagnostics))
        addSubview(copyButton)

        exportButton = UI.smallButton("Export Logs\u{2026}", target: self, action: #selector(exportLogs))
        addSubview(exportButton)

        let footerLabel = UI.label("Made with \u{2764} by Alex Karatai", font: .systemFont(ofSize: 10))
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.alignment = .center
        addSubview(footerLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            versionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            descLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 16),
            descLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
            descLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30),

            githubButton.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 18),
            githubButton.trailingAnchor.constraint(equalTo: centerXAnchor, constant: -8),

            changelogButton.centerYAnchor.constraint(equalTo: githubButton.centerYAnchor),
            changelogButton.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 8),

            copyButton.topAnchor.constraint(equalTo: githubButton.bottomAnchor, constant: 10),
            copyButton.centerXAnchor.constraint(equalTo: centerXAnchor),

            exportButton.topAnchor.constraint(equalTo: copyButton.bottomAnchor, constant: 8),
            exportButton.centerXAnchor.constraint(equalTo: centerXAnchor),

            footerLabel.topAnchor.constraint(greaterThanOrEqualTo: exportButton.bottomAnchor, constant: 20),
            footerLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            footerLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Actions

    @objc private func openGitHub() {
        guard let url = URL(string: Self.repoURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openChangelog() {
        guard let url = URL(string: Self.releasesURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(makeReport().formatted, forType: .string)

        // Confirm in place — a modal for a clipboard write would be heavy-handed.
        copyButton.title = "Copied \u{2713}"
        copyResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.copyButton.title = "Copy Diagnostic Info"
            self?.copyResetWork = nil
        }
        copyResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)

        Log.info("Diagnostic info copied to clipboard")
    }

    /// Writes the app's own log to a file the user can attach to an issue.
    ///
    /// Pairs with **Copy Diagnostic Info**: that says what the settings are, this
    /// says what actually happened — including, since 2.2.0, whether the Dock
    /// honoured each change.
    @objc private func exportLogs() {
        exportButton.isEnabled = false
        exportButton.title = "Collecting\u{2026}"

        Task { [weak self] in
            let text = await Self.collectLog()

            guard let self else { return }
            self.exportButton.isEnabled = true
            self.exportButton.title = "Export Logs\u{2026}"

            guard let text, !text.isEmpty else {
                Log.error("Log export produced nothing")
                NSSound.beep()
                return
            }
            self.presentSavePanel(for: text)
        }
    }

    // MARK: - Private

    /// Runs `log show` off the main thread — it reads a system store and can take
    /// a few seconds, which would freeze the window if done inline.
    private static func collectLog() async -> String? {
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
                    // Strip the account name out of logged bundle paths before this
                    // ever reaches an issue tracker.
                    continuation.resume(
                        returning: LogExport.redacting(raw, homeDirectory: NSHomeDirectory()))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func presentSavePanel(for text: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = LogExport.defaultFileName(at: Date())
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                Log.info("Exported log to \(url.lastPathComponent)")
            } catch {
                Log.error("Failed to write exported log: \(error)")
                NSSound.beep()
            }
        }
    }

    private func makeReport() -> DiagnosticReport {
        let prefs = UserPreferences.shared
        let info = Bundle.main.infoDictionary

        return DiagnosticReport(
            appVersion: Bundle.main.shortVersion,
            buildNumber: info?["CFBundleVersion"] as? String ?? "?",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            isAccessibilityGranted: AccessibilityChecker.isGranted,
            externalDisplayCount: service.externalDisplayCount,
            hasExternalDisplay: service.hasExternalDisplay,
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

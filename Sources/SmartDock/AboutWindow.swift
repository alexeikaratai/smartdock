import Cocoa
import SmartDockCore

/// About window with app info and links.
@MainActor
final class AboutWindow: NSObject {

    private var window: NSWindow?

    // MARK: - Public

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = makeWindow()
        window = w
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Window Construction

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "About SmartDock"
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = .clear

        let vibrancy = NSVisualEffectView()
        vibrancy.translatesAutoresizingMaskIntoConstraints = false
        vibrancy.material = .hudWindow
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        w.contentView = vibrancy
        vibrancy.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: vibrancy.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor),
        ])

        buildUI(in: contentView)
        return w
    }

    // MARK: - UI Construction

    private func buildUI(in container: NSView) {
        let version = Bundle.main.shortVersion

        // App icon
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 36, weight: .light)
        if let icon = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "SmartDock") {
            iconView.image = icon.withSymbolConfiguration(iconConfig)
            iconView.contentTintColor = .controlAccentColor
        }
        container.addSubview(iconView)

        // App name
        let nameLabel = makeLabel(text: "SmartDock", font: .systemFont(ofSize: 18, weight: .semibold))
        nameLabel.alignment = .center
        container.addSubview(nameLabel)

        // Version
        let versionLabel = makeLabel(text: "v\(version) · by Alex Karatai", font: .systemFont(ofSize: 11))
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center
        container.addSubview(versionLabel)

        // Description
        let descLabel = makeLabel(
            text: "Automatically adjusts Dock settings for your display setup.",
            font: .systemFont(ofSize: 12)
        )
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 0
        descLabel.preferredMaxLayoutWidth = 300
        container.addSubview(descLabel)

        // Link buttons
        let githubButton = makeLinkButton(title: "GitHub", action: #selector(openGitHub))
        container.addSubview(githubButton)

        let changelogButton = makeLinkButton(title: "Changelog", action: #selector(openChangelog))
        container.addSubview(changelogButton)

        // Footer
        let footerLabel = makeLabel(text: "Made with \u{2764} in Kazakhstan", font: .systemFont(ofSize: 10))
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.alignment = .center
        container.addSubview(footerLabel)

        // Layout
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 32),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            nameLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            versionLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            descLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 16),
            descLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),

            githubButton.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 18),
            githubButton.trailingAnchor.constraint(equalTo: container.centerXAnchor, constant: -8),

            changelogButton.centerYAnchor.constraint(equalTo: githubButton.centerYAnchor),
            changelogButton.leadingAnchor.constraint(equalTo: container.centerXAnchor, constant: 8),

            footerLabel.topAnchor.constraint(greaterThanOrEqualTo: githubButton.bottomAnchor, constant: 16),
            footerLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Actions

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/alexeikaratai/smartdock") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openChangelog() {
        if let url = URL(string: "https://github.com/alexeikaratai/smartdock/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func makeLabel(text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        return label
    }

    private func makeLinkButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        return btn
    }
}

// MARK: - NSWindowDelegate

extension AboutWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

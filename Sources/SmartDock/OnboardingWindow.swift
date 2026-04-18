import Cocoa
import SmartDockCore

/// Welcome screen shown once on first launch.
/// Explains what SmartDock does, then opens Settings.
@MainActor
final class OnboardingWindow: NSObject {

    private var window: NSWindow?

    /// Callback fired when user clicks "Get Started".
    var onComplete: (() -> Void)?

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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "Welcome to SmartDock"
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = .clear
        w.minSize = NSSize(width: 400, height: 400)
        w.maxSize = NSSize(width: 400, height: 400)

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
        let margin: CGFloat = 32

        // App icon
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 48, weight: .light)
        if let icon = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "SmartDock") {
            iconView.image = icon.withSymbolConfiguration(iconConfig)
            iconView.contentTintColor = .controlAccentColor
        }
        container.addSubview(iconView)

        // App name
        let nameLabel = makeLabel(text: "SmartDock", font: .systemFont(ofSize: 22, weight: .semibold))
        nameLabel.alignment = .center
        container.addSubview(nameLabel)

        // Version
        let version = Bundle.main.shortVersion
        let versionLabel = makeLabel(text: "v\(version) · by Alex Karatai", font: .systemFont(ofSize: 11))
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center
        container.addSubview(versionLabel)

        // Description
        let descLabel = makeLabel(
            text: "SmartDock automatically adjusts your Dock settings when you connect or disconnect an external monitor.",
            font: .systemFont(ofSize: 13)
        )
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 0
        descLabel.preferredMaxLayoutWidth = 340
        container.addSubview(descLabel)

        // Feature list
        let features = [
            "Auto-hide on built-in display",
            "Show dock on external monitor",
            "Position, size, magnification per mode",
        ]
        let featureStack = NSStackView()
        featureStack.translatesAutoresizingMaskIntoConstraints = false
        featureStack.orientation = .vertical
        featureStack.alignment = .leading
        featureStack.spacing = 6

        for feature in features {
            let label = makeLabel(text: "  \(feature)", font: .systemFont(ofSize: 12))
            label.textColor = .secondaryLabelColor
            featureStack.addArrangedSubview(label)
        }
        container.addSubview(featureStack)

        // Get Started button
        let button = NSButton(title: "Get Started", target: self, action: #selector(getStarted))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.keyEquivalent = "\r"
        container.addSubview(button)

        // Layout
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            nameLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            versionLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            descLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 20),
            descLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            featureStack.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 16),
            featureStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            button.topAnchor.constraint(greaterThanOrEqualTo: featureStack.bottomAnchor, constant: 24),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -28),
        ])
    }

    // MARK: - Actions

    @objc private func getStarted() {
        window?.close() // windowWillClose sets hasSeenOnboarding = true
        onComplete?()
    }

    // MARK: - Helpers

    private func makeLabel(text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        return label
    }
}

// MARK: - NSWindowDelegate

extension OnboardingWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Mark as seen even if user closes via X button
        UserPreferences.shared.hasSeenOnboarding = true
        window = nil
    }
}

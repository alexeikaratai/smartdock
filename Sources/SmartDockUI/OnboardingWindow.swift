import Cocoa
import SmartDockCore

/// Welcome screen shown once on first launch.
/// Explains what SmartDock does, then opens Settings.
@MainActor
public final class OnboardingWindow: NSObject {

    private let prefs: UserPreferences
    var window: NSWindow?  // internal so a test can reach the button

    /// Callback fired when user clicks "Get Started".
    public var onComplete: (() -> Void)?

    // MARK: - Public

    // MARK: - Init

    public init(prefs: UserPreferences = .shared) {
        self.prefs = prefs
        super.init()
    }

    public func show() {
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
        let (w, contentView) = UI.glassWindow(
            title: "Welcome to SmartDock",
            size: NSSize(width: 400, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView]
        )
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
        let nameLabel = UI.label("SmartDock", font: .systemFont(ofSize: 22, weight: .semibold))
        nameLabel.alignment = .center
        container.addSubview(nameLabel)

        // Version
        let version = Bundle.main.shortVersion
        let versionLabel = UI.label("v\(version) · by Alex Karatai", font: .systemFont(ofSize: 11))
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center
        container.addSubview(versionLabel)

        // Description
        let descLabel = UI.label(
            "SmartDock automatically adjusts your Dock settings when you connect or disconnect an external monitor.",
            font: .systemFont(ofSize: 13)
        )
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 0
        descLabel.preferredMaxLayoutWidth = 340
        container.addSubview(descLabel)

        // Feature list
        let features = [
            "Your Dock as it is becomes both profiles — nothing changes until you edit one",
            "Position, size, auto-hide, magnification per display setup",
            "Switch from the menu bar, a hotkey, a URL or a script",
        ]
        let featureStack = NSStackView()
        featureStack.translatesAutoresizingMaskIntoConstraints = false
        featureStack.orientation = .vertical
        featureStack.alignment = .leading
        featureStack.spacing = 6

        for feature in features {
            let label = UI.label("  \(feature)", font: .systemFont(ofSize: 12))
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
        window?.close()  // windowWillClose sets hasSeenOnboarding = true
        onComplete?()
    }
}

// MARK: - NSWindowDelegate

extension OnboardingWindow: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        // Mark as seen even if user closes via X button
        prefs.hasSeenOnboarding = true
        window = nil
    }
}

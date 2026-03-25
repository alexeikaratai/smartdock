import Cocoa
import SmartDockCore

/// Settings window for SmartDock.
/// Shows app info, creator, version, and configuration options.
/// Built entirely with Auto Layout — no hardcoded coordinates.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let service: SmartDockService

    // Controls that need updating
    private var launchAtLoginCheckbox: NSButton!
    private var serviceToggle: NSButton!

    init(service: SmartDockService) {
        self.service = service
        super.init()
    }

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
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "SmartDock Settings"
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.backgroundColor = .windowBackgroundColor

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        w.contentView = contentView

        buildUI(in: contentView)

        return w
    }

    // MARK: - Auto Layout UI

    private func buildUI(in container: NSView) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        // --- App Icon ---
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .light)
        if let icon = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "SmartDock") {
            iconView.image = icon.withSymbolConfiguration(config)
        }
        iconView.imageAlignment = .alignCenter
        container.addSubview(iconView)

        // --- App Name ---
        let nameLabel = makeLabel(text: "SmartDock", font: .systemFont(ofSize: 20, weight: .semibold))
        nameLabel.alignment = .center
        container.addSubview(nameLabel)

        // --- Version ---
        let versionLabel = makeLabel(text: "Version \(version) (\(build))", font: .systemFont(ofSize: 12))
        versionLabel.alignment = .center
        versionLabel.textColor = .secondaryLabelColor
        container.addSubview(versionLabel)

        // --- Creator ---
        let creatorLabel = makeLabel(text: "by Alex Karatai", font: .systemFont(ofSize: 11))
        creatorLabel.alignment = .center
        creatorLabel.textColor = .tertiaryLabelColor
        container.addSubview(creatorLabel)

        // --- Separator 1 ---
        let sep1 = NSBox()
        sep1.translatesAutoresizingMaskIntoConstraints = false
        sep1.boxType = .separator
        container.addSubview(sep1)

        // --- Settings Header ---
        let settingsHeader = makeLabel(text: "SETTINGS", font: .systemFont(ofSize: 11, weight: .medium))
        settingsHeader.textColor = .secondaryLabelColor
        container.addSubview(settingsHeader)

        // --- Service Toggle ---
        serviceToggle = NSButton(checkboxWithTitle: "Enable SmartDock", target: self, action: #selector(toggleServiceAction))
        serviceToggle.translatesAutoresizingMaskIntoConstraints = false
        serviceToggle.state = service.isEnabled ? .on : .off
        container.addSubview(serviceToggle)

        // --- Launch at Login ---
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLaunchAtLoginAction))
        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        container.addSubview(launchAtLoginCheckbox)

        // --- Separator 2 ---
        let sep2 = NSBox()
        sep2.translatesAutoresizingMaskIntoConstraints = false
        sep2.boxType = .separator
        container.addSubview(sep2)

        // --- About Header ---
        let aboutHeader = makeLabel(text: "ABOUT", font: .systemFont(ofSize: 11, weight: .medium))
        aboutHeader.textColor = .secondaryLabelColor
        container.addSubview(aboutHeader)

        // --- Description ---
        let descLabel = makeLabel(
            text: "SmartDock automatically shows the Dock when an external monitor is connected and hides it when using the built-in display only.",
            font: .systemFont(ofSize: 12)
        )
        descLabel.textColor = .labelColor
        descLabel.maximumNumberOfLines = 0
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.addSubview(descLabel)

        // --- Constraints ---
        let margin: CGFloat = 24
        let spacing: CGFloat = 4

        NSLayoutConstraint.activate([
            // Icon
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            // Name
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            // Version
            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: spacing),
            versionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            versionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            // Creator
            creatorLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 2),
            creatorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            creatorLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            // Separator 1
            sep1.topAnchor.constraint(equalTo: creatorLabel.bottomAnchor, constant: 16),
            sep1.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            sep1.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            // Settings Header
            settingsHeader.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: 14),
            settingsHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            settingsHeader.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            // Service toggle
            serviceToggle.topAnchor.constraint(equalTo: settingsHeader.bottomAnchor, constant: 10),
            serviceToggle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            serviceToggle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            // Launch at Login
            launchAtLoginCheckbox.topAnchor.constraint(equalTo: serviceToggle.bottomAnchor, constant: 8),
            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            launchAtLoginCheckbox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            // Separator 2
            sep2.topAnchor.constraint(equalTo: launchAtLoginCheckbox.bottomAnchor, constant: 16),
            sep2.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            sep2.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            // About Header
            aboutHeader.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: 14),
            aboutHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            aboutHeader.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            // Description
            descLabel.topAnchor.constraint(equalTo: aboutHeader.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
            descLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Actions

    @objc private func toggleServiceAction(_ sender: NSButton) {
        if sender.state == .on {
            service.start()
        } else {
            service.stop()
        }
    }

    @objc private func toggleLaunchAtLoginAction(_ sender: NSButton) {
        LaunchAtLogin.toggle()
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    // MARK: - Helpers

    private func makeLabel(text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        return label
    }
}

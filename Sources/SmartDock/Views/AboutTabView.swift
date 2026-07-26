import Cocoa

// MARK: - About Tab

/// Contents of the Settings window's About tab: app identity plus links.
@MainActor
final class AboutTabView: NSView {

    private static let repoURL = "https://github.com/alexeikaratai/smartdock"
    private static let releasesURL = "https://github.com/alexeikaratai/smartdock/releases"

    // MARK: - Init

    init() {
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

        let versionLabel = UI.label("v\(Bundle.main.shortVersion) · by Alex Karatai",
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

            footerLabel.topAnchor.constraint(greaterThanOrEqualTo: githubButton.bottomAnchor, constant: 20),
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
}

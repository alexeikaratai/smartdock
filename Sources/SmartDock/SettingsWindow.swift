import Cocoa
import SmartDockCore

/// Settings window for SmartDock.
/// Three tabs: Settings (dock config + general), Shortcuts (hotkey bindings), About.
@MainActor
final class SettingsWindow: NSObject {

    // MARK: - Types

    enum Tab: Int {
        case settings = 0
        case shortcuts = 1
        case about = 2
    }

    enum Mode: Int {
        case external = 0
        case builtin = 1
    }

    // MARK: - Properties

    private var window: NSWindow?
    private let service: SmartDockService
    private let hotkeyManager: HotkeyManager
    private let prefs = UserPreferences.shared

    private var currentTab: Tab = .settings
    private var selectedMode: Mode = .external
    private var selectedPosition: DockPosition = .bottom

    // Controls — Top-level
    private var headerIconView: NSImageView!
    private var tabControl: NSSegmentedControl!
    private var settingsContainer: NSView!
    private var shortcutsContainer: NSView!
    private var aboutContainer: NSView!
    private var statusLabel: NSTextField!

    // Controls — Settings tab
    private var modeControl: NSSegmentedControl!
    private var positionButtons: [DockPosition: NSButton] = [:]
    private var positionImageViews: [DockPosition: NSImageView] = [:]
    private var positionLabels: [DockPosition: NSTextField] = [:]
    private var autohideCheckbox: NSButton!
    private var iconSizeSlider: NSSlider!
    private var iconSizeLabel: NSTextField!
    private var magnificationCheckbox: NSButton!
    private var magSizeSlider: NSSlider!
    private var magSizeLabel: NSTextField!
    private var applyButton: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var notificationsCheckbox: NSButton!
    private var syncFromSystemCheckbox: NSButton!

    // Controls — Shortcuts tab
    private var hotkeyButtons: [HotkeyAction: NSButton] = [:]
    private var recordingMonitor: Any?
    private var recordingAction: HotkeyAction?

    // Cached position icons
    private lazy var positionIconCache: [DockPosition: [Bool: NSImage]] = {
        var cache: [DockPosition: [Bool: NSImage]] = [:]
        for position in DockPosition.allCases {
            cache[position] = [
                true: drawPositionIcon(for: position, selected: true),
                false: drawPositionIcon(for: position, selected: false),
            ]
        }
        return cache
    }()

    // MARK: - Init

    init(service: SmartDockService, hotkeyManager: HotkeyManager) {
        self.service = service
        self.hotkeyManager = hotkeyManager
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .smartDockStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotificationPermissionChanged),
            name: .smartDockNotificationPermissionChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    func show(tab: Tab = .settings) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            selectTab(tab)
            return
        }

        let w = makeWindow()
        window = w
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        selectedMode = service.hasExternalDisplay ? .external : .builtin
        modeControl.selectedSegment = selectedMode.rawValue
        loadCurrentMode()
        selectTab(tab)
    }

    // MARK: - Window Construction

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 660),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "SmartDock"
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = .clear
        w.minSize = NSSize(width: 420, height: 660)
        w.maxSize = NSSize(width: 420, height: 660)

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
        let margin: CGFloat = 24

        // --- Header ---
        headerIconView = NSImageView()
        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        headerIconView.imageAlignment = .alignCenter
        container.addSubview(headerIconView)

        let nameLabel = makeLabel(text: "SmartDock", font: .systemFont(ofSize: 18, weight: .semibold))
        container.addSubview(nameLabel)

        let versionLabel = makeLabel(text: "v\(version) · Made with \u{2764} by Alex Karatai", font: .systemFont(ofSize: 11))
        versionLabel.textColor = .tertiaryLabelColor
        container.addSubview(versionLabel)

        // --- Tab Control ---
        tabControl = NSSegmentedControl(
            labels: ["Settings", "Shortcuts", "About"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(tabChanged)
        )
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        tabControl.selectedSegment = 0
        tabControl.segmentStyle = .automatic
        container.addSubview(tabControl)

        // --- Containers ---
        settingsContainer = NSView()
        settingsContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(settingsContainer)

        shortcutsContainer = NSView()
        shortcutsContainer.translatesAutoresizingMaskIntoConstraints = false
        shortcutsContainer.isHidden = true
        container.addSubview(shortcutsContainer)

        aboutContainer = NSView()
        aboutContainer.translatesAutoresizingMaskIntoConstraints = false
        aboutContainer.isHidden = true
        container.addSubview(aboutContainer)

        // --- Build tab contents ---
        buildSettingsTab(in: settingsContainer)
        buildShortcutsTab(in: shortcutsContainer)
        buildAboutTab(in: aboutContainer)

        // --- Top-level layout ---
        NSLayoutConstraint.activate([
            headerIconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            headerIconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            headerIconView.widthAnchor.constraint(equalToConstant: 36),
            headerIconView.heightAnchor.constraint(equalToConstant: 36),

            nameLabel.centerYAnchor.constraint(equalTo: headerIconView.centerYAnchor, constant: -8),
            nameLabel.leadingAnchor.constraint(equalTo: headerIconView.trailingAnchor, constant: 10),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            versionLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),

            tabControl.topAnchor.constraint(equalTo: headerIconView.bottomAnchor, constant: 18),
            tabControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            tabControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            // All containers share same frame below tab control
            settingsContainer.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 14),
            settingsContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            settingsContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            shortcutsContainer.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 14),
            shortcutsContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shortcutsContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            aboutContainer.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 14),
            aboutContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            aboutContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),

        ])
    }

    // MARK: - Settings Tab

    private func buildSettingsTab(in container: NSView) {
        let margin: CGFloat = 24

        // Mode control (External / Built-in)
        modeControl = NSSegmentedControl(
            labels: ["External Monitor", "Built-in Only"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeChanged)
        )
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.selectedSegment = 0
        modeControl.segmentStyle = .automatic

        // Glass card — mode control goes inside as first element
        let card = makeGlassCard()
        container.addSubview(card)

        card.addSubview(modeControl)

        let posLabel = makeLabel(text: "Dock Position", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(posLabel)

        let posStack = makePositionPicker()
        card.addSubview(posStack)

        autohideCheckbox = NSButton(checkboxWithTitle: "Auto-hide Dock", target: self, action: #selector(settingChanged))
        autohideCheckbox.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(autohideCheckbox)

        let sizeTitle = makeLabel(text: "Icon Size", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(sizeTitle)

        iconSizeSlider = NSSlider(value: 0.29, minValue: 0, maxValue: 1, target: self, action: #selector(sliderChanged))
        iconSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        iconSizeSlider.isContinuous = true
        card.addSubview(iconSizeSlider)

        iconSizeLabel = makeLabel(text: "Small \u{25C0}\u{2500}\u{25B6} Large", font: .systemFont(ofSize: 10))
        iconSizeLabel.textColor = .tertiaryLabelColor
        iconSizeLabel.alignment = .center
        card.addSubview(iconSizeLabel)

        magnificationCheckbox = NSButton(checkboxWithTitle: "Magnification", target: self, action: #selector(settingChanged))
        magnificationCheckbox.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(magnificationCheckbox)

        let magTitle = makeLabel(text: "Magnification Size", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(magTitle)

        magSizeSlider = NSSlider(value: 0.43, minValue: 0, maxValue: 1, target: self, action: #selector(sliderChanged))
        magSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        magSizeSlider.isContinuous = true
        card.addSubview(magSizeSlider)

        magSizeLabel = makeLabel(text: "Small \u{25C0}\u{2500}\u{25B6} Large", font: .systemFont(ofSize: 10))
        magSizeLabel.textColor = .tertiaryLabelColor
        magSizeLabel.alignment = .center
        card.addSubview(magSizeLabel)

        applyButton = NSButton(title: "Apply", target: self, action: #selector(applySettings))
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.bezelStyle = .rounded
        applyButton.controlSize = .large
        applyButton.keyEquivalent = "\r"
        applyButton.isEnabled = false
        card.addSubview(applyButton)

        // General + buttons outside card
        let generalHeader = makeLabel(text: "GENERAL", font: .systemFont(ofSize: 11, weight: .medium))
        generalHeader.textColor = .secondaryLabelColor
        container.addSubview(generalHeader)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        container.addSubview(launchAtLoginCheckbox)

        notificationsCheckbox = NSButton(checkboxWithTitle: "Notify on Profile Switch", target: self, action: #selector(toggleNotifications))
        notificationsCheckbox.translatesAutoresizingMaskIntoConstraints = false
        notificationsCheckbox.state = prefs.notificationsEnabled ? .on : .off
        container.addSubview(notificationsCheckbox)

        syncFromSystemCheckbox = NSButton(checkboxWithTitle: "Auto-import System changes", target: self, action: #selector(toggleSyncFromSystem))
        syncFromSystemCheckbox.translatesAutoresizingMaskIntoConstraints = false
        syncFromSystemCheckbox.state = prefs.syncFromSystemEnabled ? .on : .off
        container.addSubview(syncFromSystemCheckbox)

        let syncButton = NSButton(title: "Sync from System", target: self, action: #selector(syncFromSystem))
        syncButton.translatesAutoresizingMaskIntoConstraints = false
        syncButton.bezelStyle = .rounded
        syncButton.controlSize = .small
        container.addSubview(syncButton)

        let refreshButton = NSButton(title: "Refresh Now", target: self, action: #selector(refreshNow))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        container.addSubview(refreshButton)

        let quitButton = NSButton(title: "Quit SmartDock", target: self, action: #selector(quitApp))
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        container.addSubview(quitButton)

        statusLabel = makeLabel(text: statusText(), font: .systemFont(ofSize: 11))
        statusLabel.textColor = .tertiaryLabelColor
        container.addSubview(statusLabel)

        // Layout
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin - 4),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(margin - 4)),

            modeControl.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            modeControl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            modeControl.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            posLabel.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 14),
            posLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            posStack.topAnchor.constraint(equalTo: posLabel.bottomAnchor, constant: 10),
            posStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            posStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            posStack.heightAnchor.constraint(equalToConstant: 60),

            autohideCheckbox.topAnchor.constraint(equalTo: posStack.bottomAnchor, constant: 14),
            autohideCheckbox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            sizeTitle.topAnchor.constraint(equalTo: autohideCheckbox.bottomAnchor, constant: 16),
            sizeTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            iconSizeLabel.centerYAnchor.constraint(equalTo: sizeTitle.centerYAnchor),
            iconSizeLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            iconSizeLabel.widthAnchor.constraint(equalToConstant: 50),

            iconSizeSlider.topAnchor.constraint(equalTo: sizeTitle.bottomAnchor, constant: 6),
            iconSizeSlider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconSizeSlider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            magnificationCheckbox.topAnchor.constraint(equalTo: iconSizeSlider.bottomAnchor, constant: 14),
            magnificationCheckbox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            magTitle.topAnchor.constraint(equalTo: magnificationCheckbox.bottomAnchor, constant: 12),
            magTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            magSizeLabel.centerYAnchor.constraint(equalTo: magTitle.centerYAnchor),
            magSizeLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            magSizeLabel.widthAnchor.constraint(equalToConstant: 50),

            magSizeSlider.topAnchor.constraint(equalTo: magTitle.bottomAnchor, constant: 6),
            magSizeSlider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            magSizeSlider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            applyButton.topAnchor.constraint(equalTo: magSizeSlider.bottomAnchor, constant: 16),
            applyButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            applyButton.widthAnchor.constraint(equalToConstant: 120),
            applyButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),

            // General — below card
            generalHeader.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 14),
            generalHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            launchAtLoginCheckbox.topAnchor.constraint(equalTo: generalHeader.bottomAnchor, constant: 8),
            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            notificationsCheckbox.topAnchor.constraint(equalTo: launchAtLoginCheckbox.bottomAnchor, constant: 8),
            notificationsCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            syncFromSystemCheckbox.topAnchor.constraint(equalTo: notificationsCheckbox.bottomAnchor, constant: 8),
            syncFromSystemCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            syncButton.topAnchor.constraint(equalTo: syncFromSystemCheckbox.bottomAnchor, constant: 12),
            syncButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            refreshButton.centerYAnchor.constraint(equalTo: syncButton.centerYAnchor),
            refreshButton.leadingAnchor.constraint(equalTo: syncButton.trailingAnchor, constant: 8),

            quitButton.centerYAnchor.constraint(equalTo: syncButton.centerYAnchor),
            quitButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),

            statusLabel.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Shortcuts Tab

    private func buildShortcutsTab(in container: NSView) {
        let margin: CGFloat = 24

        let header = makeLabel(text: "Configure global keyboard shortcuts.", font: .systemFont(ofSize: 12))
        header.textColor = .secondaryLabelColor
        container.addSubview(header)

        var hotkeyLabels: [NSTextField] = []
        for action in HotkeyAction.allCases {
            let label = makeLabel(text: action.displayName, font: .systemFont(ofSize: 13))
            container.addSubview(label)
            hotkeyLabels.append(label)

            let btn = makeHotkeyButton(for: action)
            container.addSubview(btn)
            hotkeyButtons[action] = btn
        }

        let hint = makeLabel(text: "Click to record, Esc to clear", font: .systemFont(ofSize: 10))
        hint.textColor = .tertiaryLabelColor
        container.addSubview(hint)

        // Layout
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
        ])

        var previousAnchor = header.bottomAnchor
        for (index, action) in HotkeyAction.allCases.enumerated() {
            let label = hotkeyLabels[index]
            let btn = hotkeyButtons[action]!
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: previousAnchor, constant: 12),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
                btn.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                btn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
                btn.widthAnchor.constraint(equalToConstant: 120),
            ])
            previousAnchor = label.bottomAnchor
        }

        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: previousAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            hint.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - About Tab

    private func buildAboutTab(in container: NSView) {
        let version = Bundle.main.shortVersion

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 36, weight: .light)
        if let icon = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "SmartDock") {
            iconView.image = icon.withSymbolConfiguration(iconConfig)
            iconView.contentTintColor = .controlAccentColor
        }
        container.addSubview(iconView)

        let nameLabel = makeLabel(text: "SmartDock", font: .systemFont(ofSize: 18, weight: .semibold))
        nameLabel.alignment = .center
        container.addSubview(nameLabel)

        let versionLabel = makeLabel(text: "v\(version) · by Alex Karatai", font: .systemFont(ofSize: 11))
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center
        container.addSubview(versionLabel)

        let descLabel = makeLabel(
            text: "Automatically adjusts Dock settings for your display setup.",
            font: .systemFont(ofSize: 12)
        )
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 0
        descLabel.lineBreakMode = .byWordWrapping
        container.addSubview(descLabel)

        let githubButton = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        githubButton.translatesAutoresizingMaskIntoConstraints = false
        githubButton.bezelStyle = .rounded
        githubButton.controlSize = .small
        container.addSubview(githubButton)

        let changelogButton = NSButton(title: "Changelog", target: self, action: #selector(openChangelog))
        changelogButton.translatesAutoresizingMaskIntoConstraints = false
        changelogButton.bezelStyle = .rounded
        changelogButton.controlSize = .small
        container.addSubview(changelogButton)

        let footerLabel = makeLabel(text: "Made with \u{2764} by Alex Karatai", font: .systemFont(ofSize: 10))
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.alignment = .center
        container.addSubview(footerLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
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

            footerLabel.topAnchor.constraint(greaterThanOrEqualTo: githubButton.bottomAnchor, constant: 20),
            footerLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            footerLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Tab Switching

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        guard let tab = Tab(rawValue: sender.selectedSegment) else { return }
        selectTab(tab)
    }

    private func selectTab(_ tab: Tab) {
        // Auto-save if leaving Settings with unsaved changes
        if currentTab == .settings && tab != .settings && applyButton.isEnabled {
            saveAndApply()
        }

        // Cancel hotkey recording if leaving Shortcuts
        if currentTab == .shortcuts && tab != .shortcuts && recordingAction != nil {
            stopRecording()
        }

        currentTab = tab
        tabControl.selectedSegment = tab.rawValue

        settingsContainer.isHidden = tab != .settings
        shortcutsContainer.isHidden = tab != .shortcuts
        aboutContainer.isHidden = tab != .about
    }

    // MARK: - Position Icon Picker

    private func makePositionPicker() -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually

        for position in DockPosition.allCases {
            let btn = makePositionButton(for: position)
            positionButtons[position] = btn
            stack.addArrangedSubview(btn)
        }

        return stack
    }

    private func makePositionButton(for position: DockPosition) -> NSButton {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.title = ""
        btn.bezelStyle = .smallSquare
        btn.isBordered = false
        btn.setButtonType(.momentaryPushIn)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.target = self
        btn.action = #selector(positionButtonTapped(_:))
        btn.tag = DockPosition.allCases.firstIndex(of: position) ?? 0

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = positionIconCache[position]?[false]
        imageView.imageAlignment = .alignCenter
        btn.addSubview(imageView)
        positionImageViews[position] = imageView

        let label = NSTextField(labelWithString: position.displayName)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        btn.addSubview(label)
        positionLabels[position] = label

        NSLayoutConstraint.activate([
            btn.heightAnchor.constraint(equalToConstant: 60),
            imageView.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: btn.topAnchor, constant: 8),
            imageView.widthAnchor.constraint(equalToConstant: 44),
            imageView.heightAnchor.constraint(equalToConstant: 32),
            label.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
        ])

        return btn
    }

    private func updatePositionSelection() {
        for (position, btn) in positionButtons {
            let isSelected = position == selectedPosition
            btn.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
                : NSColor.clear.cgColor
            positionImageViews[position]?.image = positionIconCache[position]?[isSelected]
            positionLabels[position]?.textColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        }
    }

    private func drawPositionIcon(for position: DockPosition, selected: Bool) -> NSImage {
        let size = NSSize(width: 44, height: 32)
        return NSImage(size: size, flipped: true) { rect in
            let monitorRect = rect.insetBy(dx: 3, dy: 3)
            let accentColor = NSColor.controlAccentColor

            let outline = NSBezierPath(roundedRect: monitorRect, xRadius: 4, yRadius: 4)
            if selected {
                accentColor.withAlphaComponent(0.08).setFill()
                outline.fill()
                accentColor.withAlphaComponent(0.6).setStroke()
            } else {
                NSColor.tertiaryLabelColor.withAlphaComponent(0.5).setStroke()
            }
            outline.lineWidth = 1.2
            outline.stroke()

            let barColor = selected ? accentColor : NSColor.secondaryLabelColor
            let dotColor = selected
                ? accentColor.withAlphaComponent(0.5)
                : NSColor.tertiaryLabelColor

            let barRect: NSRect
            switch position {
            case .bottom:
                barRect = NSRect(x: monitorRect.minX + 5, y: monitorRect.maxY - 6,
                                 width: monitorRect.width - 10, height: 3.5)
            case .left:
                barRect = NSRect(x: monitorRect.minX + 2, y: monitorRect.minY + 4,
                                 width: 3.5, height: monitorRect.height - 8)
            case .right:
                barRect = NSRect(x: monitorRect.maxX - 5.5, y: monitorRect.minY + 4,
                                 width: 3.5, height: monitorRect.height - 8)
            }

            barColor.setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5).fill()

            let isHorizontal = position == .bottom
            let dotCount = isHorizontal ? 4 : 3
            let dotSize: CGFloat = 2
            let dotSpacing: CGFloat = isHorizontal ? 4 : 3.5
            let totalSpan = CGFloat(dotCount) * dotSize + CGFloat(dotCount - 1) * dotSpacing

            dotColor.setFill()
            for i in 0..<dotCount {
                let offset = CGFloat(i) * (dotSize + dotSpacing)
                let dotRect: NSRect
                if isHorizontal {
                    let startX = barRect.midX - totalSpan / 2
                    let dotY = barRect.minY + (barRect.height - dotSize) / 2
                    dotRect = NSRect(x: startX + offset, y: dotY,
                                     width: dotSize, height: dotSize)
                } else {
                    let dotX = barRect.minX + (barRect.width - dotSize) / 2
                    let startY = barRect.midY - totalSpan / 2
                    dotRect = NSRect(x: dotX, y: startY + offset,
                                     width: dotSize, height: dotSize)
                }
                NSBezierPath(roundedRect: dotRect, xRadius: 0.5, yRadius: 0.5).fill()
            }

            return true
        }
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        if applyButton.isEnabled { saveAndApply() }
        selectedMode = Mode(rawValue: sender.selectedSegment) ?? .external
        loadCurrentMode()
    }

    @objc private func positionButtonTapped(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < DockPosition.allCases.count else { return }
        selectedPosition = DockPosition.allCases[idx]
        updatePositionSelection()
        headerIconView.image = drawPositionIcon(for: selectedPosition, selected: true)
        markDirty()
    }

    @objc private func settingChanged(_ sender: Any) {
        magSizeSlider.isEnabled = magnificationCheckbox.state == .on
        markDirty()
    }

    @objc private func sliderChanged(_ sender: NSSlider) { markDirty() }
    @objc private func applySettings(_ sender: Any) { saveAndApply() }
    @objc private func refreshNow(_ sender: Any) { service.refresh() }
    @objc private func quitApp(_ sender: Any) { NSApp.terminate(nil) }

    @objc private func syncFromSystem(_ sender: NSButton) {
        let systemConfig = service.dockController.readSystemConfig()
        if selectedMode == .external {
            prefs.externalConfig = systemConfig
        } else {
            prefs.builtinConfig = systemConfig
        }
        loadCurrentMode()
        applyButton.isEnabled = false
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        LaunchAtLogin.toggle()
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func toggleNotifications(_ sender: NSButton) {
        let enabled = sender.state == .on
        prefs.notificationsEnabled = enabled
        if enabled {
            NotificationCenter.default.post(name: .smartDockRequestNotificationAuth, object: nil)
        }
    }

    @objc private func toggleSyncFromSystem(_ sender: NSButton) {
        prefs.syncFromSystemEnabled = sender.state == .on
    }

    @objc private func handleNotificationPermissionChanged(_ notification: Notification) {
        notificationsCheckbox.state = prefs.notificationsEnabled ? .on : .off
    }

    @objc private func hotkeyButtonClicked(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < HotkeyAction.allCases.count else { return }
        let action = HotkeyAction.allCases[sender.tag]
        if recordingAction != nil { stopRecording(); return }
        startRecording(action: action, button: sender)
    }

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

    // MARK: - Hotkey Recording

    private func startRecording(action: HotkeyAction, button: NSButton) {
        recordingAction = action
        hotkeyManager.isRecording = true
        button.title = "Press shortcut..."

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handleRecordedKey(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
        recordingAction = nil
        hotkeyManager.isRecording = false
        hotkeyManager.reloadBindings()
        updateHotkeyButtons()
    }

    private func handleRecordedKey(_ event: NSEvent) {
        guard let action = recordingAction else { return }

        if event.keyCode == 53 {
            prefs.setHotkey(nil, for: action.rawValue)
            stopRecording()
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let hasModifier = modifiers.contains(.command) || modifiers.contains(.control)
            || modifiers.contains(.option)
        guard hasModifier else { return }

        let displayName = event.charactersIgnoringModifiers?.uppercased() ?? "?"
        let binding = HotkeyBinding(
            keyCode: event.keyCode,
            modifiers: modifiers.rawValue,
            displayName: displayName
        )
        prefs.setHotkey(binding, for: action.rawValue)
        stopRecording()
    }

    private func updateHotkeyButtons() {
        for action in HotkeyAction.allCases {
            hotkeyButtons[action]?.title = hotkeyDisplayString(for: action)
        }
    }

    private func hotkeyDisplayString(for action: HotkeyAction) -> String {
        guard let binding = prefs.hotkey(for: action.rawValue) else { return "Click to set" }
        return HotkeyManager.displayString(for: binding)
    }

    /// Display state changed — refresh Settings UI.
    @objc private func handleStateChange(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        if applyButton.isEnabled { saveAndApply() }
        loadCurrentMode()
    }

    // MARK: - Dirty State

    private func markDirty() { applyButton.isEnabled = true }

    // MARK: - Load / Save

    private func loadCurrentMode() {
        let config = selectedMode == .external ? prefs.externalConfig : prefs.builtinConfig

        selectedPosition = config.position
        updatePositionSelection()

        autohideCheckbox.state = config.autohide ? .on : .off
        iconSizeSlider.doubleValue = config.iconSize
        magnificationCheckbox.state = config.magnification ? .on : .off
        magSizeSlider.doubleValue = config.magnificationSize
        magSizeSlider.isEnabled = config.magnification

        updateStatus()
        updateHeaderIcon()
    }

    private func updateHeaderIcon() {
        let config = selectedMode == .external ? prefs.externalConfig : prefs.builtinConfig
        headerIconView.image = drawPositionIcon(for: config.position, selected: true)
    }

    private func saveAndApply() {
        let config = DockConfiguration(
            autohide: autohideCheckbox.state == .on,
            position: selectedPosition,
            iconSize: iconSizeSlider.doubleValue,
            magnification: magnificationCheckbox.state == .on,
            magnificationSize: magSizeSlider.doubleValue
        )

        if selectedMode == .external {
            prefs.externalConfig = config
        } else {
            prefs.builtinConfig = config
        }

        let editingActiveMode = (selectedMode == .external && service.hasExternalDisplay)
            || (selectedMode == .builtin && !service.hasExternalDisplay)

        applyButton.isEnabled = false
        if editingActiveMode { service.refresh() }
        updateStatus()
    }

    private func updateStatus() { statusLabel.stringValue = statusText() }

    private func statusText() -> String {
        let mode = service.hasExternalDisplay ? "External monitor connected" : "Built-in display only"
        return "Current: \(mode)"
    }

    // MARK: - Helpers

    private func makeLabel(text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        return label
    }

    private func makeHotkeyButton(for action: HotkeyAction) -> NSButton {
        let btn = NSButton(title: hotkeyDisplayString(for: action), target: self, action: #selector(hotkeyButtonClicked))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.tag = HotkeyAction.allCases.firstIndex(of: action) ?? 0
        return btn
    }

    private func makeGlassCard() -> NSVisualEffectView {
        let card = NSVisualEffectView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.material = .popover
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        return card
    }
}

// MARK: - NSWindowDelegate

extension SettingsWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if recordingAction != nil { stopRecording() }
        window = nil
    }
}

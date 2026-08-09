import Cocoa
import SmartDockCore

/// Settings window for SmartDock.
/// Three tabs: Settings (dock config + general), Shortcuts (hotkey bindings), About.
///
/// The self-contained pieces live in their own types: `PositionPicker`,
/// `AccessibilityWarningView`, `AboutTabView`, `HotkeyRecorder`.
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
    private var keyMonitor: Any?
    private let service: SmartDockService
    private let hotkeyRecorder: HotkeyRecorder
    private let prefs = UserPreferences.shared

    private var currentTab: Tab = .settings
    private var selectedMode: Mode = .external

    // Controls — Top-level
    private var headerIconView: NSImageView!
    private var tabControl: NSSegmentedControl!
    private var settingsContainer: NSView!
    private var shortcutsContainer: NSView!
    private var aboutContainer: NSView!
    private var statusLabel: NSTextField!

    // Controls — Settings tab
    private var modeControl: NSSegmentedControl!
    private var positionPicker: PositionPicker!
    private var autohideCheckbox: NSButton!
    private var iconSizeSlider: NSSlider!
    private var magnificationCheckbox: NSButton!
    private var magSizeSlider: NSSlider!
    private var applyButton: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var notificationsCheckbox: NSButton!
    private var syncFromSystemCheckbox: NSButton!

    // Controls — Shortcuts tab
    private var hotkeyButtons: [HotkeyAction: NSButton] = [:]

    // MARK: - Init

    init(service: SmartDockService, hotkeyManager: HotkeyManager) {
        self.service = service
        self.hotkeyRecorder = HotkeyRecorder(hotkeyManager: hotkeyManager)
        super.init()

        hotkeyRecorder.onFinish = { [weak self] in
            self?.updateHotkeyButtons()
        }

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

        installKeyMonitor()

        selectedMode = service.hasExternalDisplay ? .external : .builtin
        modeControl.selectedSegment = selectedMode.rawValue
        loadCurrentMode()
        selectTab(tab)
    }

    /// Installs a local key monitor for ⌘0 (reset window size) and Escape (close window).
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // ⌘0 — reset window to default size
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "0" {
                self.window?.setContentSize(Self.defaultContentSize)
                self.window?.center()
                return nil
            }

            // Escape — close window (but skip while recording a hotkey; that flow owns Escape)
            if event.keyCode == 53, !self.hotkeyRecorder.isRecording {
                self.window?.performClose(nil)
                return nil
            }

            return event
        }
    }

    // MARK: - Window Construction

    private static let defaultContentSize = NSSize(width: 420, height: 660)

    private func makeWindow() -> NSWindow {
        let (w, contentView) = UI.glassWindow(
            title: "SmartDock",
            size: Self.defaultContentSize,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView]
        )

        // Bounded resize range — user can shrink down to minimum readable size.
        w.contentMinSize = NSSize(width: 380, height: 500)
        w.contentMaxSize = NSSize(width: 600, height: 900)
        w.setContentSize(Self.defaultContentSize)

        // Don't persist resized frame across sessions — always open at default.
        w.setFrameAutosaveName("")

        buildUI(in: contentView)
        return w
    }

    // MARK: - UI Construction

    private func buildUI(in container: NSView) {
        let margin: CGFloat = 24

        // --- Header ---
        headerIconView = NSImageView()
        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        headerIconView.imageAlignment = .alignCenter
        container.addSubview(headerIconView)

        let nameLabel = UI.label("SmartDock", font: .systemFont(ofSize: 18, weight: .semibold))
        container.addSubview(nameLabel)

        let versionLabel = UI.label(
            "v\(Bundle.main.shortVersion) · Made with \u{2764} by Alex Karatai",
            font: .systemFont(ofSize: 11))
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

        aboutContainer = AboutTabView(service: service)
        aboutContainer.isHidden = true
        container.addSubview(aboutContainer)

        // --- Build tab contents ---
        buildSettingsTab(in: settingsContainer)
        buildShortcutsTab(in: shortcutsContainer)

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
        let card = UI.glassCard()
        container.addSubview(card)

        card.addSubview(modeControl)

        let posLabel = UI.label("Dock Position", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(posLabel)

        positionPicker = PositionPicker()
        positionPicker.onSelectionChange = { [weak self] position in
            guard let self else { return }
            self.headerIconView.image = PositionIcon.image(for: position, selected: true)
            self.markDirty()
        }
        card.addSubview(positionPicker)

        autohideCheckbox = UI.checkbox("Auto-hide Dock", target: self, action: #selector(settingChanged))
        card.addSubview(autohideCheckbox)

        let sizeTitle = UI.label("Icon Size", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(sizeTitle)

        iconSizeSlider = UI.scaleSlider(value: 0.29, target: self, action: #selector(sliderChanged))
        card.addSubview(iconSizeSlider)

        let iconSizeLabel = makeScaleHintLabel()
        card.addSubview(iconSizeLabel)

        magnificationCheckbox = UI.checkbox("Magnification", target: self, action: #selector(settingChanged))
        card.addSubview(magnificationCheckbox)

        let magTitle = UI.label("Magnification Size", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(magTitle)

        magSizeSlider = UI.scaleSlider(value: 0.43, target: self, action: #selector(sliderChanged))
        card.addSubview(magSizeSlider)

        let magSizeLabel = makeScaleHintLabel()
        card.addSubview(magSizeLabel)

        applyButton = NSButton(title: "Apply", target: self, action: #selector(applySettings))
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.bezelStyle = .rounded
        applyButton.controlSize = .large
        applyButton.keyEquivalent = "\r"
        applyButton.isEnabled = false
        card.addSubview(applyButton)

        // General + buttons outside card
        let generalHeader = UI.label("GENERAL", font: .systemFont(ofSize: 11, weight: .medium))
        generalHeader.textColor = .secondaryLabelColor
        container.addSubview(generalHeader)

        launchAtLoginCheckbox = UI.checkbox(
            "Launch at Login", target: self,
            action: #selector(toggleLaunchAtLogin))
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        container.addSubview(launchAtLoginCheckbox)

        notificationsCheckbox = UI.checkbox(
            "Notify on Profile Switch", target: self,
            action: #selector(toggleNotifications))
        notificationsCheckbox.state = prefs.notificationsEnabled ? .on : .off
        container.addSubview(notificationsCheckbox)

        syncFromSystemCheckbox = UI.checkbox(
            "Auto-import System changes", target: self,
            action: #selector(toggleSyncFromSystem))
        syncFromSystemCheckbox.state = prefs.syncFromSystemEnabled ? .on : .off
        container.addSubview(syncFromSystemCheckbox)

        let syncButton = UI.smallButton("Sync from System", target: self, action: #selector(syncFromSystem))
        container.addSubview(syncButton)

        let refreshButton = UI.smallButton("Refresh Now", target: self, action: #selector(refreshNow))
        container.addSubview(refreshButton)

        let quitButton = UI.smallButton("Quit SmartDock", target: self, action: #selector(quitApp))
        container.addSubview(quitButton)

        statusLabel = UI.label(statusText(), font: .systemFont(ofSize: 11))
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

            positionPicker.topAnchor.constraint(equalTo: posLabel.bottomAnchor, constant: 10),
            positionPicker.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            positionPicker.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            positionPicker.heightAnchor.constraint(equalToConstant: PositionPicker.buttonHeight),

            autohideCheckbox.topAnchor.constraint(equalTo: positionPicker.bottomAnchor, constant: 14),
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

        let header = UI.label("Configure global keyboard shortcuts.", font: .systemFont(ofSize: 12))
        header.textColor = .secondaryLabelColor
        container.addSubview(header)

        // Only shown when Accessibility permission is missing
        let accessibilityWarning = AccessibilityWarningView()
        container.addSubview(accessibilityWarning)

        var hotkeyLabels: [NSTextField] = []
        for action in HotkeyAction.allCases {
            let label = UI.label(action.displayName, font: .systemFont(ofSize: 13))
            container.addSubview(label)
            hotkeyLabels.append(label)

            let button = makeHotkeyButton(for: action)
            container.addSubview(button)
            hotkeyButtons[action] = button
        }

        let hint = UI.label("Click to record, Esc to clear", font: .systemFont(ofSize: 10))
        hint.textColor = .tertiaryLabelColor
        container.addSubview(hint)

        // Layout
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            accessibilityWarning.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            accessibilityWarning.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin - 4),
            accessibilityWarning.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(margin - 4)),
        ])

        var previousAnchor = accessibilityWarning.bottomAnchor
        for (index, action) in HotkeyAction.allCases.enumerated() {
            let label = hotkeyLabels[index]
            guard let button = hotkeyButtons[action] else { continue }
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: previousAnchor, constant: 12),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
                button.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
                button.widthAnchor.constraint(equalToConstant: 120),
            ])
            previousAnchor = label.bottomAnchor
        }

        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: previousAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            hint.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
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
        if currentTab == .shortcuts && tab != .shortcuts && hotkeyRecorder.isRecording {
            hotkeyRecorder.stop()
        }

        currentTab = tab
        tabControl.selectedSegment = tab.rawValue

        settingsContainer.isHidden = tab != .settings
        shortcutsContainer.isHidden = tab != .shortcuts
        aboutContainer.isHidden = tab != .about
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        if applyButton.isEnabled { saveAndApply() }
        selectedMode = Mode(rawValue: sender.selectedSegment) ?? .external
        loadCurrentMode()
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
        if hotkeyRecorder.isRecording {
            hotkeyRecorder.stop()
            return
        }
        hotkeyRecorder.start(HotkeyAction.allCases[sender.tag], in: sender)
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
        let config = activeConfig

        positionPicker.selectedPosition = config.position
        autohideCheckbox.state = config.autohide ? .on : .off
        iconSizeSlider.doubleValue = config.iconSize
        magnificationCheckbox.state = config.magnification ? .on : .off
        magSizeSlider.doubleValue = config.magnificationSize
        magSizeSlider.isEnabled = config.magnification

        headerIconView.image = PositionIcon.image(for: config.position, selected: true)
        updateStatus()
    }

    private func saveAndApply() {
        let config = DockConfiguration(
            autohide: autohideCheckbox.state == .on,
            position: positionPicker.selectedPosition,
            iconSize: iconSizeSlider.doubleValue,
            magnification: magnificationCheckbox.state == .on,
            magnificationSize: magSizeSlider.doubleValue
        )

        if selectedMode == .external {
            prefs.externalConfig = config
        } else {
            prefs.builtinConfig = config
        }

        let editingActiveMode =
            (selectedMode == .external && service.hasExternalDisplay)
            || (selectedMode == .builtin && !service.hasExternalDisplay)

        applyButton.isEnabled = false
        if editingActiveMode { service.refresh() }
        updateStatus()
    }

    /// Stored config for the mode currently shown in the Settings tab.
    private var activeConfig: DockConfiguration {
        selectedMode == .external ? prefs.externalConfig : prefs.builtinConfig
    }

    // MARK: - Helpers

    private func updateStatus() { statusLabel.stringValue = statusText() }

    private func statusText() -> String {
        let mode = service.hasExternalDisplay ? "External monitor connected" : "Built-in display only"
        return "Current: \(mode)"
    }

    /// "Small ◀─▶ Large" caption shown beside a size slider.
    private func makeScaleHintLabel() -> NSTextField {
        let label = UI.label("Small \u{25C0}\u{2500}\u{25B6} Large", font: .systemFont(ofSize: 10))
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        return label
    }

    private func makeHotkeyButton(for action: HotkeyAction) -> NSButton {
        let button = UI.smallButton(
            HotkeyRecorder.displayTitle(for: action),
            target: self,
            action: #selector(hotkeyButtonClicked)
        )
        button.tag = HotkeyAction.allCases.firstIndex(of: action) ?? 0
        return button
    }

    private func updateHotkeyButtons() {
        for action in HotkeyAction.allCases {
            hotkeyButtons[action]?.title = HotkeyRecorder.displayTitle(for: action)
        }
    }
}

// MARK: - NSWindowDelegate

extension SettingsWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if hotkeyRecorder.isRecording { hotkeyRecorder.stop() }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        window = nil
    }
}

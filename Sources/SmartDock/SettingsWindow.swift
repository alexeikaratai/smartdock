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

    /// Raw values are the segment indices of `tabControl` — the two are read off each
    /// other in `selectTab` and `tabChanged`, so they have to stay in the same order.
    enum Tab: Int {
        case dock = 0
        case general = 1
        case shortcuts = 2
        case about = 3
    }

    typealias Mode = DockTabView.Mode

    // MARK: - Properties

    private var window: NSWindow?
    private var keyMonitor: Any?
    private let service: SmartDockService
    private let hotkeyRecorder: HotkeyRecorder
    private let prefs = UserPreferences.shared

    private var currentTab: Tab = .dock
    private var selectedMode: Mode = .external

    // Controls — Top-level
    private var headerIconView: NSImageView!
    private var tabControl: NSSegmentedControl!
    private var dockTab: DockTabView!
    private var settingsScroll: NSScrollView!
    private var generalContainer: GeneralTabView!
    private var shortcutsContainer: NSView!
    private var aboutContainer: NSView!

    // Controls — Settings tab

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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    func show(tab: Tab = .dock) {
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

        selectedMode = Mode(service.activeProfile)
        dockTab.selectedMode = selectedMode
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

    /// Tall enough that no tab scrolls at the default size. Measured: the Dock tab
    /// needs 600pt (552 before the indicator and minimize-into-app toggles) and
    /// General 116, with the header and tab control above them taking another 118.
    /// The scroll view on the Dock tab stays as the safety net for a shrunk window —
    /// it is not a substitute for a size that fits.
    private static let defaultContentSize = NSSize(width: 420, height: 720)

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
            labels: ["Dock", "General", "Shortcuts", "About"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(tabChanged)
        )
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        tabControl.selectedSegment = 0
        tabControl.segmentStyle = .automatic
        container.addSubview(tabControl)

        // --- Containers ---
        // Dock is the one tab whose content can outgrow the window, and the only
        // one that can be scrolled: `DockTabView` defines its height from the inside
        // (its status line is pinned to its bottom), while Shortcuts and About end in
        // `lessThanOrEqualTo` and rely on the window stretching them — inside a
        // scroll view their height would be undefined.
        //
        // Without this the container was pinned top and sides but never to the
        // bottom, so anything past the window edge was quietly clipped. No constraint
        // conflicted, so Auto Layout never said a word about it.
        dockTab = DockTabView()
        dockTab.onModeChange = { [weak self] mode in self?.modeChanged(to: mode) }
        dockTab.onEdited = { [weak self] in
            guard let self else { return }
            self.headerIconView.image = PositionIcon.image(for: self.dockTab.configuration.position, selected: true)
            self.markDirty()
        }
        dockTab.onApply = { [weak self] in self?.saveAndApply() }
        dockTab.onDiscard = { [weak self] in self?.discardChanges() }
        dockTab.onUseCurrentDock = { [weak self] in self?.useCurrentDock() }
        dockTab.onSyncFromSystem = { [weak self] in self?.syncFromSystem() }

        settingsScroll = NSScrollView()
        settingsScroll.translatesAutoresizingMaskIntoConstraints = false
        settingsScroll.hasVerticalScroller = true
        settingsScroll.autohidesScrollers = true
        settingsScroll.drawsBackground = false
        settingsScroll.documentView = dockTab
        container.addSubview(settingsScroll)

        generalContainer = GeneralTabView(service: service, prefs: prefs)
        generalContainer.isHidden = true
        container.addSubview(generalContainer)

        shortcutsContainer = NSView()
        shortcutsContainer.translatesAutoresizingMaskIntoConstraints = false
        shortcutsContainer.isHidden = true
        container.addSubview(shortcutsContainer)

        aboutContainer = AboutTabView(service: service)
        aboutContainer.isHidden = true
        container.addSubview(aboutContainer)

        // --- Build tab contents ---
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
            settingsScroll.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 14),
            settingsScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            settingsScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            settingsScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Width tied to the clip view so the tab never scrolls sideways; height
            // is left to the content, which is what gives the scroller something to
            // scroll when the card grows.
            dockTab.topAnchor.constraint(equalTo: settingsScroll.contentView.topAnchor),
            dockTab.leadingAnchor.constraint(
                equalTo: settingsScroll.contentView.leadingAnchor),
            dockTab.trailingAnchor.constraint(
                equalTo: settingsScroll.contentView.trailingAnchor),
            dockTab.widthAnchor.constraint(
                equalTo: settingsScroll.contentView.widthAnchor),

            generalContainer.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 14),
            generalContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            generalContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            shortcutsContainer.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 14),
            shortcutsContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shortcutsContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            aboutContainer.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 14),
            aboutContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            aboutContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
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
        // A draft on the Dock tab survives a tab switch untouched. It used to be
        // applied here, which turned "let me look at Shortcuts for a second" into a
        // change to the Dock the user never confirmed.

        // Cancel hotkey recording if leaving Shortcuts
        if currentTab == .shortcuts && tab != .shortcuts && hotkeyRecorder.isRecording {
            hotkeyRecorder.stop()
        }

        currentTab = tab
        tabControl.selectedSegment = tab.rawValue

        settingsScroll.isHidden = tab != .dock
        generalContainer.isHidden = tab != .general
        shortcutsContainer.isHidden = tab != .shortcuts
        aboutContainer.isHidden = tab != .about
    }

    // MARK: - Actions

    private func modeChanged(to target: Mode) {
        guard target != selectedMode else { return }

        // The form is about to show a different profile, so a draft here really
        // would be lost — this is the one place a question is warranted.
        if isDirty {
            switch askAboutDraft() {
            case .apply: saveAndApply()
            case .discard: break
            case .cancel:
                dockTab.selectedMode = selectedMode
                return
            }
        }
        selectedMode = target
        loadCurrentMode()
        markClean()
    }

    private enum DraftDecision { case apply, discard, cancel }

    /// Apply / Discard / Cancel for a draft that is about to be lost. Only two paths
    /// reach it — switching profiles and closing the window. Everything else keeps
    /// the draft where it is.
    private func askAboutDraft() -> DraftDecision {
        let alert = NSAlert()
        alert.messageText = "Apply changes to the \(selectedMode.title) profile?"
        alert.informativeText = "The Dock settings you changed have not been applied."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .apply
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    /// Seeds the form from the live Dock, leaving the Dock itself untouched.
    ///
    /// Reads through the controller rather than the service's `currentConfig`: that
    /// one is what SmartDock last *asked* for, and the point here is what the Dock
    /// actually holds — the two differ whenever macOS refused a setting.
    private func useCurrentDock() {
        populate(from: service.dockController.readSystemConfig())
        markDirty()
        Log.info("Settings: seeded the form from the live Dock")
    }
    private func syncFromSystem() {
        prefs[selectedMode.profile] = service.dockController.readSystemConfig()
        loadCurrentMode()
        markClean()
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
    /// A display change or a verified apply while the window is open. Refreshes what
    /// describes the outside world — status, active-profile marker, refusal — and
    /// leaves the form alone if it holds a draft. It used to apply the draft first, on
    /// the reasoning that reloading would lose it; plugging in a monitor mid-edit
    /// therefore committed whatever the sliders happened to be at.
    @objc private func handleStateChange(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        updateStatus()
        updateModeTitles()
        updateRefusalNotice()
        if !isDirty { loadCurrentMode() }
    }

    // MARK: - Dirty State

    private var isDirty: Bool { dockTab.isDirty }
    private func markDirty() { dockTab.isDirty = true }
    private func markClean() { dockTab.isDirty = false }

    private func discardChanges() {
        loadCurrentMode()
        markClean()
    }

    // MARK: - Load / Save

    private func loadCurrentMode() {
        populate(from: activeConfig)
        updateStatus()
        updateModeTitles()
        updateRefusalNotice()
    }

    /// Fills every control from a configuration.
    ///
    /// Shared by loading a stored profile and by **Use Current Dock**, so the two
    /// cannot drift: a control added to the form but forgotten in one of them would
    /// show a stale value from the other.
    private func populate(from config: DockConfiguration) {
        dockTab.configuration = config
        headerIconView.image = PositionIcon.image(for: config.position, selected: true)
    }

    private func saveAndApply() {
        prefs[selectedMode.profile] = dockTab.configuration

        markClean()
        // Re-applying the profile by name keeps an on-request override in force;
        // `refresh()` would re-derive it from the displays and silently drop it.
        if selectedMode.profile == service.activeProfile { service.applyProfile(selectedMode.profile) }
        updateStatus()
    }

    /// Stored config for the mode currently shown in the Settings tab.
    private var activeConfig: DockConfiguration { prefs[selectedMode.profile] }

    // MARK: - Helpers

    private func updateStatus() { dockTab.status = statusText() }

    private func statusText() -> String { "Current: \(service.activeProfileDescription)" }

    private func updateModeTitles() { dockTab.markActive(Mode(service.activeProfile)) }

    private func updateRefusalNotice() {
        dockTab.refusalNotice = service.dockController.lastApplyOutcome?.refusalNotice
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
    /// Closing used to drop a draft without a word, while every other exit applied
    /// it — inconsistent in both directions. Now it asks, and Cancel keeps the window.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isDirty else { return true }
        switch askAboutDraft() {
        case .apply:
            saveAndApply()
            return true
        case .discard: return true
        case .cancel: return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        if hotkeyRecorder.isRecording { hotkeyRecorder.stop() }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        window = nil
    }
}

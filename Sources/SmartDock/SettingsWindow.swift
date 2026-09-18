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

    enum Mode: Int {
        case external = 0
        case builtin = 1

        var title: String {
            switch self {
            case .external: return "External Monitor"
            case .builtin: return "Built-in Only"
            }
        }

        var profile: DockProfile {
            switch self {
            case .external: .external
            case .builtin: .builtin
            }
        }

        init(_ profile: DockProfile) {
            switch profile {
            case .external: self = .external
            case .builtin: self = .builtin
            }
        }
    }

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
    private var settingsContainer: NSView!
    private var settingsScroll: NSScrollView!
    private var generalContainer: GeneralTabView!
    private var shortcutsContainer: NSView!
    private var aboutContainer: NSView!
    private var statusLabel: NSTextField!

    // Controls — Settings tab
    private var modeControl: NSSegmentedControl!
    private var positionPicker: PositionPicker!
    private var autohideCheckbox: NSButton!
    private var iconSizeSlider: NSSlider!
    private var magnificationCheckbox: NSButton!
    private var minimizeEffectPopup: NSPopUpButton!
    private var animateCheckbox: NSButton!
    private var recentsCheckbox: NSButton!
    private var magSizeSlider: NSSlider!
    private var applyButton: NSButton!
    private var useCurrentButton: NSButton!
    private var discardButton: NSButton!
    private var buttonRow: NSStackView!
    private var refusalLabel: NSTextField!
    private var iconSizeValueLabel: NSTextField!
    private var magSizeValueLabel: NSTextField!

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

    /// Tall enough that no tab scrolls at the default size. Measured: the Dock tab
    /// needs 552pt and General 116, with the header and tab control above them taking
    /// another 120. The scroll view on the Dock tab stays as the safety net for a
    /// shrunk window — it is not a substitute for a size that fits.
    private static let defaultContentSize = NSSize(width: 420, height: 680)

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
        // Settings is the one tab whose content can outgrow the window, and the only
        // one that can be scrolled: its height is fully defined from the inside
        // (`statusLabel` is pinned to the bottom), while Shortcuts and About end in
        // `lessThanOrEqualTo` and rely on the window stretching them — inside a
        // scroll view their height would be undefined.
        //
        // Without this the container was pinned top and sides but never to the
        // bottom, so anything past the window edge was quietly clipped. No constraint
        // conflicted, so Auto Layout never said a word about it.
        settingsContainer = NSView()
        settingsContainer.translatesAutoresizingMaskIntoConstraints = false

        settingsScroll = NSScrollView()
        settingsScroll.translatesAutoresizingMaskIntoConstraints = false
        settingsScroll.hasVerticalScroller = true
        settingsScroll.autohidesScrollers = true
        settingsScroll.drawsBackground = false
        settingsScroll.documentView = settingsContainer
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
            settingsScroll.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 14),
            settingsScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            settingsScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            settingsScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Width tied to the clip view so the tab never scrolls sideways; height
            // is left to the content, which is what gives the scroller something to
            // scroll when the card grows.
            settingsContainer.topAnchor.constraint(equalTo: settingsScroll.contentView.topAnchor),
            settingsContainer.leadingAnchor.constraint(
                equalTo: settingsScroll.contentView.leadingAnchor),
            settingsContainer.trailingAnchor.constraint(
                equalTo: settingsScroll.contentView.trailingAnchor),
            settingsContainer.widthAnchor.constraint(
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

    // MARK: - Settings Tab

    private func buildSettingsTab(in container: NSView) {
        let margin: CGFloat = 24

        // Names what the control below actually does. Without it the segmented
        // control reads as a mode switch for the app rather than a choice of which
        // profile the form is editing.
        let editingLabel = UI.label("EDITING PROFILE", font: .systemFont(ofSize: 11, weight: .medium))
        editingLabel.textColor = .secondaryLabelColor

        // Mode control (External / Built-in). Segment titles are refreshed by
        // `updateModeTitles` so the active profile carries a marker.
        modeControl = NSSegmentedControl(
            labels: [Mode.external.title, Mode.builtin.title],
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

        card.addSubview(editingLabel)
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

        iconSizeValueLabel = makeValueLabel()
        let iconSizeLabel = iconSizeValueLabel!
        card.addSubview(iconSizeLabel)

        magnificationCheckbox = UI.checkbox("Magnification", target: self, action: #selector(settingChanged))
        card.addSubview(magnificationCheckbox)

        let magTitle = UI.label("Magnification Size", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(magTitle)

        magSizeSlider = UI.scaleSlider(value: 0.43, target: self, action: #selector(sliderChanged))
        card.addSubview(magSizeSlider)

        magSizeValueLabel = makeValueLabel()
        let magSizeLabel = magSizeValueLabel!
        card.addSubview(magSizeLabel)

        let minimizeTitle = UI.label("Minimize Effect", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(minimizeTitle)

        // Only the two effects System Events exposes — the enum is the source of
        // the list, so a third case would appear here without touching this file.
        minimizeEffectPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        minimizeEffectPopup.translatesAutoresizingMaskIntoConstraints = false
        minimizeEffectPopup.addItems(withTitles: MinimizeEffect.allCases.map(\.displayName))
        minimizeEffectPopup.target = self
        minimizeEffectPopup.action = #selector(settingChanged)
        card.addSubview(minimizeEffectPopup)

        animateCheckbox = UI.checkbox(
            "Animate opening applications", target: self, action: #selector(settingChanged))
        card.addSubview(animateCheckbox)

        recentsCheckbox = UI.checkbox(
            "Show recent applications", target: self, action: #selector(settingChanged))
        card.addSubview(recentsCheckbox)

        applyButton = NSButton(title: "Apply", target: self, action: #selector(applySettings))
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.bezelStyle = .rounded
        applyButton.controlSize = .large
        applyButton.keyEquivalent = "\r"
        applyButton.isEnabled = false

        // Fills the form from the Dock as it is right now. Deliberately does not
        // apply anything: it seeds the fields and lights up Apply, so the change is
        // still the user's to confirm. Without it a profile has to be rebuilt from
        // scratch — position, two sliders, three toggles and a popup — even when the
        // Dock is already set up the way they want it saved.
        useCurrentButton = NSButton(
            title: "Use Current Dock", target: self, action: #selector(useCurrentDock))
        useCurrentButton.translatesAutoresizingMaskIntoConstraints = false
        useCurrentButton.bezelStyle = .rounded
        useCurrentButton.controlSize = .large

        // A stack so the two are laid out as one unit; their labels differ in width
        // and always will, so centring them individually cannot come out symmetrical.
        // Reloads the stored profile and drops the draft. Until it existed the only
        // way out of an experiment was to close the window — which threw the draft
        // away silently — or to switch tabs, which applied it silently.
        discardButton = NSButton(title: "Discard", target: self, action: #selector(discardChanges))
        discardButton.translatesAutoresizingMaskIntoConstraints = false
        discardButton.bezelStyle = .rounded
        discardButton.controlSize = .large
        discardButton.isEnabled = false

        buttonRow = NSStackView(views: [useCurrentButton, discardButton, applyButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        card.addSubview(buttonRow)

        // Names a setting macOS refused, right under the button that asked for it.
        // The same fact has been in the menu bar since 2.5.3, but that is not where
        // a person is looking a second after pressing Apply.
        refusalLabel = UI.label("", font: .systemFont(ofSize: 11))
        refusalLabel.textColor = .systemOrange
        refusalLabel.alignment = .center
        refusalLabel.isHidden = true
        card.addSubview(refusalLabel)

        // Stays with the profile it acts on: it writes the live Dock into whichever
        // mode is selected above, so separating it from that picker would leave a
        // button whose effect depends on a control on another tab.
        let syncButton = UI.smallButton("Sync from System", target: self, action: #selector(syncFromSystem))
        container.addSubview(syncButton)

        statusLabel = UI.label(statusText(), font: .systemFont(ofSize: 11))
        statusLabel.textColor = .tertiaryLabelColor
        container.addSubview(statusLabel)

        // Layout
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin - 4),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(margin - 4)),

            editingLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            editingLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            modeControl.topAnchor.constraint(equalTo: editingLabel.bottomAnchor, constant: 6),
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

            minimizeTitle.topAnchor.constraint(equalTo: magSizeSlider.bottomAnchor, constant: 16),
            minimizeTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            minimizeEffectPopup.centerYAnchor.constraint(equalTo: minimizeTitle.centerYAnchor),
            minimizeEffectPopup.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            minimizeEffectPopup.leadingAnchor.constraint(
                greaterThanOrEqualTo: minimizeTitle.trailingAnchor, constant: 12),

            animateCheckbox.topAnchor.constraint(equalTo: minimizeTitle.bottomAnchor, constant: 14),
            animateCheckbox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            recentsCheckbox.topAnchor.constraint(equalTo: animateCheckbox.bottomAnchor, constant: 8),
            recentsCheckbox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            // Centred as a group, with Apply on the right where the confirming button
            // belongs. Pinning each button to `card.centerXAnchor` separately centres
            // the *gap* instead, which leaves a pair of unequal buttons visibly off to
            // one side — 20pt to the left, with these two labels.
            buttonRow.topAnchor.constraint(equalTo: recentsCheckbox.bottomAnchor, constant: 16),
            buttonRow.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            refusalLabel.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 8),
            refusalLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            refusalLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            refusalLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            applyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),

            syncButton.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 14),
            syncButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            statusLabel.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 10),
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

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        let target = Mode(rawValue: sender.selectedSegment) ?? .external
        guard target != selectedMode else { return }

        // The form is about to show a different profile, so a draft here really
        // would be lost — this is the one place a question is warranted.
        if isDirty {
            switch askAboutDraft() {
            case .apply: saveAndApply()
            case .discard: break
            case .cancel:
                sender.selectedSegment = selectedMode.rawValue
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

    @objc private func settingChanged(_ sender: Any) {
        magSizeSlider.isEnabled = magnificationCheckbox.state == .on
        markDirty()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        updateSizeLabels()
        markDirty()
    }
    @objc private func applySettings(_ sender: Any) { saveAndApply() }

    /// Seeds the form from the live Dock, leaving the Dock itself untouched.
    ///
    /// Reads through the controller rather than the service's `currentConfig`: that
    /// one is what SmartDock last *asked* for, and the point here is what the Dock
    /// actually holds — the two differ whenever macOS refused a setting.
    @objc private func useCurrentDock(_ sender: Any) {
        populate(from: service.dockController.readSystemConfig())
        markDirty()
        Log.info("Settings: seeded the form from the live Dock")
    }
    @objc private func syncFromSystem(_ sender: NSButton) {
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

    private var isDirty: Bool { applyButton.isEnabled }

    private func markDirty() {
        applyButton.isEnabled = true
        discardButton.isEnabled = true
    }

    private func markClean() {
        applyButton.isEnabled = false
        discardButton.isEnabled = false
    }

    @objc private func discardChanges(_ sender: Any) {
        loadCurrentMode()
        markClean()
    }

    /// Resolves the popup back to a case by index rather than by title — the popup
    /// is populated from `allCases` in the same order, and matching on the displayed
    /// string would break the moment a name is reworded.
    private var selectedMinimizeEffect: MinimizeEffect {
        let index = minimizeEffectPopup.indexOfSelectedItem
        guard MinimizeEffect.allCases.indices.contains(index) else { return .genie }
        return MinimizeEffect.allCases[index]
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
        positionPicker.selectedPosition = config.position
        autohideCheckbox.state = config.autohide ? .on : .off
        iconSizeSlider.doubleValue = config.iconSize
        magnificationCheckbox.state = config.magnification ? .on : .off
        magSizeSlider.doubleValue = config.magnificationSize
        magSizeSlider.isEnabled = config.magnification
        minimizeEffectPopup.selectItem(withTitle: config.minimizeEffect.displayName)
        animateCheckbox.state = config.animatesLaunch ? .on : .off
        recentsCheckbox.state = config.showsRecents ? .on : .off
        updateSizeLabels()

        headerIconView.image = PositionIcon.image(for: config.position, selected: true)
    }

    private func saveAndApply() {
        let config = DockConfiguration(
            autohide: autohideCheckbox.state == .on,
            position: positionPicker.selectedPosition,
            iconSize: iconSizeSlider.doubleValue,
            magnification: magnificationCheckbox.state == .on,
            magnificationSize: magSizeSlider.doubleValue,
            minimizeEffect: selectedMinimizeEffect,
            animatesLaunch: animateCheckbox.state == .on,
            showsRecents: recentsCheckbox.state == .on
        )

        prefs[selectedMode.profile] = config

        markClean()
        // Re-applying the profile by name keeps an on-request override in force;
        // `refresh()` would re-derive it from the displays and silently drop it.
        if selectedMode.profile == service.activeProfile { service.applyProfile(selectedMode.profile) }
        updateStatus()
    }

    /// Stored config for the mode currently shown in the Settings tab.
    private var activeConfig: DockConfiguration { prefs[selectedMode.profile] }

    // MARK: - Helpers

    private func updateStatus() { statusLabel.stringValue = statusText() }

    private func statusText() -> String { "Current: \(service.activeProfileDescription)" }

    /// "Small ◀─▶ Large" caption shown beside a size slider.
    /// Shows the size in pixels, the unit System Settings uses. The label used to be a
    /// static "Small ◀─▶ Large" hint on the grounds that the scale is what is stored;
    /// but a person comparing against System Settings, or trying to make two profiles
    /// match, needs the number the system shows them, not a reminder of which way is up.
    private func makeValueLabel() -> NSTextField {
        let label = UI.label("", font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular))
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    private func updateSizeLabels() {
        iconSizeValueLabel.stringValue = "\(DockConfiguration.scaleToPixels(iconSizeSlider.doubleValue)) px"
        magSizeValueLabel.stringValue = "\(DockConfiguration.scaleToPixels(magSizeSlider.doubleValue)) px"
    }

    /// Marks the profile in force. The status line at the bottom said the same
    /// thing, but a person editing a profile looks at the picker, and the picker
    /// gave no hint which of the two was live.
    private func updateModeTitles() {
        let active = Mode(service.activeProfile)
        for mode in [Mode.external, .builtin] {
            let marker = mode == active ? "\u{25CF} " : ""
            modeControl.setLabel(marker + mode.title, forSegment: mode.rawValue)
        }
    }

    private func updateRefusalNotice() {
        guard let notice = service.dockController.lastApplyOutcome?.refusalNotice else {
            refusalLabel.isHidden = true
            return
        }
        refusalLabel.stringValue = "\u{26A0}\u{FE0F} \(notice)"
        refusalLabel.isHidden = false
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

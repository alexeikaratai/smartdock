import Cocoa
import SmartDockCore

/// Settings window for SmartDock.
/// Segmented control switches between External Monitor / Built-in Only modes.
/// Each mode has: position (icon picker), autohide, icon size, magnification.
@MainActor
final class SettingsWindow: NSObject {

    // MARK: - Types

    enum Mode: Int {
        case external = 0
        case builtin = 1

        var title: String {
            switch self {
            case .external: return "External Monitor"
            case .builtin:  return "Built-in Only"
            }
        }
    }

    // MARK: - Properties

    private var window: NSWindow?
    private let service: SmartDockService
    private let prefs = UserPreferences.shared

    private var selectedMode: Mode = .external
    private var selectedPosition: DockPosition = .bottom

    // Controls
    private var segmentedControl: NSSegmentedControl!
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
    private var statusLabel: NSTextField!

    // MARK: - Init

    init(service: SmartDockService) {
        self.service = service
        super.init()

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

        // Select the tab matching the current display state
        selectedMode = service.hasExternalDisplay ? .external : .builtin
        segmentedControl.selectedSegment = selectedMode.rawValue
        loadCurrentMode()
    }

    // MARK: - Window Construction

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 610),
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

        // Full-window vibrancy (glass effect)
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

        // --- App Header ---
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
        if let icon = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "SmartDock") {
            iconView.image = icon.withSymbolConfiguration(iconConfig)
            iconView.contentTintColor = .controlAccentColor
        }
        container.addSubview(iconView)

        let nameLabel = makeLabel(text: "SmartDock", font: .systemFont(ofSize: 18, weight: .semibold))
        container.addSubview(nameLabel)

        let versionLabel = makeLabel(text: "v\(version) · by Alex Karatai", font: .systemFont(ofSize: 11))
        versionLabel.textColor = .tertiaryLabelColor
        container.addSubview(versionLabel)

        // --- Segmented Control ---
        segmentedControl = NSSegmentedControl(labels: ["External Monitor", "Built-in Only"],
                                              trackingMode: .selectOne,
                                              target: self,
                                              action: #selector(modeChanged))
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegment = 0
        segmentedControl.segmentStyle = .automatic
        container.addSubview(segmentedControl)

        // --- Dock Settings Card ---
        let card = makeGlassCard()
        container.addSubview(card)

        // Position — icon radio buttons
        let posLabel = makeLabel(text: "Dock Position", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(posLabel)

        let posStack = makePositionPicker()
        card.addSubview(posStack)

        // Autohide
        autohideCheckbox = NSButton(checkboxWithTitle: "Auto-hide Dock", target: self, action: #selector(settingChanged))
        autohideCheckbox.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(autohideCheckbox)

        // Icon Size
        let sizeTitle = makeLabel(text: "Icon Size", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(sizeTitle)

        iconSizeSlider = NSSlider(value: 0.29, minValue: 0, maxValue: 1, target: self, action: #selector(sliderChanged))
        iconSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        iconSizeSlider.numberOfTickMarks = 0
        iconSizeSlider.isContinuous = true
        card.addSubview(iconSizeSlider)

        iconSizeLabel = makeLabel(text: "Small ◀─▶ Large", font: .systemFont(ofSize: 10))
        iconSizeLabel.textColor = .tertiaryLabelColor
        iconSizeLabel.alignment = .center
        card.addSubview(iconSizeLabel)

        // Magnification
        magnificationCheckbox = NSButton(checkboxWithTitle: "Magnification", target: self, action: #selector(settingChanged))
        magnificationCheckbox.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(magnificationCheckbox)

        let magTitle = makeLabel(text: "Magnification Size", font: .systemFont(ofSize: 13, weight: .medium))
        card.addSubview(magTitle)

        magSizeSlider = NSSlider(value: 0.43, minValue: 0, maxValue: 1, target: self, action: #selector(sliderChanged))
        magSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        magSizeSlider.numberOfTickMarks = 0
        magSizeSlider.isContinuous = true
        card.addSubview(magSizeSlider)

        magSizeLabel = makeLabel(text: "Small ◀─▶ Large", font: .systemFont(ofSize: 10))
        magSizeLabel.textColor = .tertiaryLabelColor
        magSizeLabel.alignment = .center
        card.addSubview(magSizeLabel)

        // --- Apply Button ---
        applyButton = NSButton(title: "Apply", target: self, action: #selector(applySettings))
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.bezelStyle = .rounded
        applyButton.controlSize = .regular
        applyButton.keyEquivalent = "\r" // Enter key
        applyButton.isEnabled = false
        container.addSubview(applyButton)

        // --- Separator ---
        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .separator
        container.addSubview(sep)

        // --- General Settings ---
        let generalHeader = makeLabel(text: "GENERAL", font: .systemFont(ofSize: 11, weight: .medium))
        generalHeader.textColor = .secondaryLabelColor
        container.addSubview(generalHeader)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        container.addSubview(launchAtLoginCheckbox)

        // Sync from System button
        let syncButton = NSButton(title: "Sync from System", target: self, action: #selector(syncFromSystem))
        syncButton.translatesAutoresizingMaskIntoConstraints = false
        syncButton.bezelStyle = .rounded
        syncButton.controlSize = .small
        container.addSubview(syncButton)

        // Refresh Now button
        let refreshButton = NSButton(title: "Refresh Now", target: self, action: #selector(refreshNow))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        container.addSubview(refreshButton)

        // Quit button
        let quitButton = NSButton(title: "Quit SmartDock", target: self, action: #selector(quitApp))
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        container.addSubview(quitButton)

        // Status
        statusLabel = makeLabel(text: statusText(), font: .systemFont(ofSize: 11))
        statusLabel.textColor = .tertiaryLabelColor
        container.addSubview(statusLabel)

        // --- Layout ---
        NSLayoutConstraint.activate([
            // Header
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),

            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor, constant: -8),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            versionLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),

            // Segmented control
            segmentedControl.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 18),
            segmentedControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            segmentedControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),

            // Card
            card.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 14),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin - 4),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -(margin - 4)),

            // Position row
            posLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            posLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            posStack.topAnchor.constraint(equalTo: posLabel.bottomAnchor, constant: 10),
            posStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            posStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            posStack.heightAnchor.constraint(equalToConstant: 60),

            // Autohide
            autohideCheckbox.topAnchor.constraint(equalTo: posStack.bottomAnchor, constant: 14),
            autohideCheckbox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            // Icon size
            sizeTitle.topAnchor.constraint(equalTo: autohideCheckbox.bottomAnchor, constant: 16),
            sizeTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            iconSizeLabel.centerYAnchor.constraint(equalTo: sizeTitle.centerYAnchor),
            iconSizeLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            iconSizeLabel.widthAnchor.constraint(equalToConstant: 50),

            iconSizeSlider.topAnchor.constraint(equalTo: sizeTitle.bottomAnchor, constant: 6),
            iconSizeSlider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconSizeSlider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            // Magnification
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
            magSizeSlider.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),

            // Apply button
            applyButton.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 12),
            applyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            // Separator
            sep.topAnchor.constraint(equalTo: applyButton.bottomAnchor, constant: 12),
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            // General
            generalHeader.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 14),
            generalHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            launchAtLoginCheckbox.topAnchor.constraint(equalTo: generalHeader.bottomAnchor, constant: 8),
            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            // Sync button
            syncButton.topAnchor.constraint(equalTo: launchAtLoginCheckbox.bottomAnchor, constant: 12),
            syncButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),

            // Refresh Now — next to Sync
            refreshButton.centerYAnchor.constraint(equalTo: syncButton.centerYAnchor),
            refreshButton.leadingAnchor.constraint(equalTo: syncButton.trailingAnchor, constant: 8),

            // Quit button — next to Refresh
            quitButton.centerYAnchor.constraint(equalTo: syncButton.centerYAnchor),
            quitButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),

            // Status
            statusLabel.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Position Icon Picker

    /// Creates a horizontal stack of icon buttons for dock position (Bottom / Left / Right).
    /// Each button shows a visual representation of where the dock would be.
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

    /// Creates a clickable view with centered icon + label for a dock position.
    private func makePositionButton(for position: DockPosition) -> NSButton {
        // Use a plain push-style button as clickable container
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

        // Icon
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = drawPositionIcon(for: position, selected: false)
        imageView.imageAlignment = .alignCenter
        btn.addSubview(imageView)
        positionImageViews[position] = imageView

        // Label
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
            positionImageViews[position]?.image = drawPositionIcon(for: position, selected: isSelected)
            positionLabels[position]?.textColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        }
    }

    /// Draws a Rectangle-style icon: rounded monitor outline with a dock bar
    /// and small app icon squares on the correct edge.
    private func drawPositionIcon(for position: DockPosition, selected: Bool) -> NSImage {
        let size = NSSize(width: 44, height: 32)
        return NSImage(size: size, flipped: true) { rect in
            let monitorRect = rect.insetBy(dx: 3, dy: 3)
            let accentColor = NSColor.controlAccentColor

            // Monitor outline — rounded rect with subtle fill
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

            // Dock bar + app icon dots
            let barColor = selected ? accentColor : NSColor.secondaryLabelColor
            let dotColor = selected
                ? accentColor.withAlphaComponent(0.5)
                : NSColor.tertiaryLabelColor

            // Dock bar rect depends on position
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

            // App icon dots along the bar
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
        // Auto-save unsaved changes before switching tab
        if applyButton.isEnabled {
            saveAndApply()
        }
        selectedMode = Mode(rawValue: sender.selectedSegment) ?? .external
        loadCurrentMode()
    }

    @objc private func positionButtonTapped(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < DockPosition.allCases.count else { return }
        selectedPosition = DockPosition.allCases[idx]
        updatePositionSelection()
        markDirty()
    }

    @objc private func settingChanged(_ sender: Any) {
        magSizeSlider.isEnabled = magnificationCheckbox.state == .on
        markDirty()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        markDirty()
    }

    @objc private func applySettings(_ sender: Any) {
        saveAndApply()
    }

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

    @objc private func refreshNow(_ sender: Any) {
        service.refresh()
    }

    @objc private func quitApp(_ sender: Any) {
        NSApp.terminate(nil)
    }

    /// Display state changed (monitor connected/disconnected) — refresh Settings UI.
    @objc private func handleStateChange(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        if applyButton.isEnabled {
            saveAndApply()
        }
        loadCurrentMode()
    }

    // MARK: - Dirty State

    /// Mark that unsaved changes exist — enable the Apply button.
    private func markDirty() {
        applyButton.isEnabled = true
    }

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
    }

    /// Save current UI state to preferences and apply to dock if this is the active mode.
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

        // Apply to dock if editing the currently active mode.
        let editingActiveMode = (selectedMode == .external && service.hasExternalDisplay)
            || (selectedMode == .builtin && !service.hasExternalDisplay)

        // Reset dirty state before refresh — refresh posts a synchronous
        // notification that calls handleStateChange, which would re-enter
        // saveAndApply if the button were still enabled.
        applyButton.isEnabled = false

        if editingActiveMode {
            service.refresh()
        }

        updateStatus()
    }

    private func updateStatus() {
        statusLabel.stringValue = statusText()
    }

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

    /// Creates a card with vibrancy material for a glass-like appearance.
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
        window = nil
    }
}

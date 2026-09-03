import Cocoa
import SmartDockCore

/// Menu bar icon controller.
/// Shows current state and allows service management.
@MainActor
final class StatusBarController: NSObject {

    private var statusItem: NSStatusItem!
    private let service: SmartDockService
    private let hotkeyManager: HotkeyManager
    private lazy var settingsWindow = SettingsWindow(service: service, hotkeyManager: hotkeyManager)

    // Cached icons: [position][visible/hidden]
    private lazy var iconCache: [DockPosition: [Bool: NSImage]] = {
        var cache: [DockPosition: [Bool: NSImage]] = [:]
        for position in DockPosition.allCases {
            cache[position] = [
                true: makeIcon(position: position, dockVisible: true),
                false: makeIcon(position: position, dockVisible: false),
            ]
        }
        return cache
    }()

    // Menu items that are updated dynamically
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var dockVisibilityMenuItem: NSMenuItem!
    private var refusalMenuItem: NSMenuItem!
    private var refreshMenuItem: NSMenuItem!

    // MARK: - Init

    init(service: SmartDockService, hotkeyManager: HotkeyManager) {
        self.service = service
        self.hotkeyManager = hotkeyManager
        super.init()
        setupStatusItem()
        service.delegate = self
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let config = service.currentConfig
            button.image =
                iconCache[config.position]?[!config.autohide]
                ?? iconCache[.bottom]?[true]
            button.toolTip = tooltipText()
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        // AppKit otherwise recomputes each item's enabled state from its target and
        // discards what this class sets, which would silently make
        // `updateActionAvailability` do nothing. The informational rows below are
        // disabled explicitly, so nothing relies on the automatic behaviour.
        menu.autoenablesItems = false

        // Title + version
        let version = Bundle.main.shortVersion
        let headerItem = NSMenuItem(title: "SmartDock v\(version)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ]
        headerItem.attributedTitle = NSAttributedString(string: "SmartDock v\(version)", attributes: attrs)
        menu.addItem(headerItem)

        // Status
        statusMenuItem = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        // Sits under the status line and stays hidden unless the Dock refused
        // something. An informational line like the one above it — the detail is in
        // the diagnostic report, and there is no action to offer for a refusal that
        // clears itself the moment nothing is fullscreen.
        refusalMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        refusalMenuItem.isEnabled = false
        refusalMenuItem.isHidden = true
        menu.addItem(refusalMenuItem)

        menu.addItem(.separator())

        // Enable/disable
        toggleMenuItem = NSMenuItem(
            title: service.isEnabled ? "Disable" : "Enable",
            action: #selector(toggleService),
            keyEquivalent: "e"
        )
        toggleMenuItem.target = self
        toggleMenuItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(toggleMenuItem)

        // Forced refresh
        refreshMenuItem = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refreshMenuItem.target = self
        refreshMenuItem.image = NSImage(
            systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(refreshMenuItem)

        // Hide/show the Dock. Title and icon follow the Dock's actual state, which
        // is why they are refreshed in `menuNeedsUpdate` rather than set once.
        dockVisibilityMenuItem = NSMenuItem(
            title: dockVisibilityTitle(),
            action: #selector(toggleDockVisibility),
            keyEquivalent: "d"
        )
        dockVisibilityMenuItem.target = self
        applyDockVisibilityAppearance()
        menu.addItem(dockVisibilityMenuItem)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        // Shortcuts
        let shortcutsItem = NSMenuItem(
            title: "Shortcuts…",
            action: #selector(openShortcuts),
            keyEquivalent: ""
        )
        shortcutsItem.target = self
        shortcutsItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        menu.addItem(shortcutsItem)

        // About
        let aboutItem = NSMenuItem(
            title: "About SmartDock",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        // Exit
        let quitItem = NSMenuItem(
            title: "Quit SmartDock",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func toggleService() {
        if service.isEnabled {
            service.stop()
        } else {
            service.start()
        }
        updateUI()
    }

    @objc private func refresh() {
        service.refresh()
    }

    func showSettings(tab: SettingsWindow.Tab = .settings) {
        settingsWindow.show(tab: tab)
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func openShortcuts() {
        settingsWindow.show(tab: .shortcuts)
    }

    @objc private func openAbout() {
        settingsWindow.show(tab: .about)
    }

    @objc private func quit() {
        service.stop()
        NSApp.terminate(nil)
    }

    // MARK: - UI Updates

    private func updateUI() {
        statusMenuItem.title = statusText()
        toggleMenuItem.title = service.isEnabled ? "Disable" : "Enable"
        dockVisibilityMenuItem.title = dockVisibilityTitle()
        applyDockVisibilityAppearance()
        updateRefusalNotice()
        updateActionAvailability()

        if let button = statusItem.button {
            // Use our saved config, not readSystemConfig() — the system config can
            // be in a transient state during fullscreen or dock transitions.
            let config = service.currentConfig
            button.image =
                iconCache[config.position]?[!config.autohide]
                ?? iconCache[.bottom]?[true]
            button.toolTip = tooltipText()
        }
    }

    private func tooltipText() -> String {
        let profile = service.hasExternalDisplay ? "External Monitor" : "Built-in Only"
        let config = service.currentConfig
        let autohide = config.autohide ? "hidden" : "visible"
        return "SmartDock — \(profile)\nDock: \(config.position.displayName), \(autohide)"
    }

    /// Runs through `HotkeyManager` rather than toggling here, so the menu joins
    /// the hotkey, `smartdock://` and AppleScript on one execution path instead of
    /// becoming a fourth implementation of the same action.
    @objc private func toggleDockVisibility() {
        hotkeyManager.perform(.toggleAutohide)
    }

    /// Names what the click will *do*, not what the state is — "Hide Dock" while
    /// the Dock is visible. A title naming the state reads as a status line and
    /// leaves people unsure which way the item will move things.
    private func dockVisibilityTitle() -> String {
        service.currentConfig.autohide ? "Show Dock" : "Hide Dock"
    }

    private func applyDockVisibilityAppearance() {
        let symbol = service.currentConfig.autohide ? "eye" : "eye.slash"
        dockVisibilityMenuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    /// Surfaces a setting the Dock refused. Read on every menu open because the
    /// outcome only becomes known a second after the apply, well after the state
    /// change that redrew everything else.
    /// Greys out the two items that act on the Dock while the service is off.
    ///
    /// The service stopped honouring them when disabled, which is right — but left
    /// clickable they looked broken, and worse, the auto-hide toggle still rewrote
    /// the stored profile, so the Dock would hide by itself on the next enable.
    /// Depends on `autoenablesItems` being off, set in `buildMenu`.
    private func updateActionAvailability() {
        refreshMenuItem.isEnabled = service.isEnabled
        dockVisibilityMenuItem.isEnabled = service.isEnabled
    }

    private func updateRefusalNotice() {
        guard let notice = service.dockController.lastApplyOutcome?.refusalNotice else {
            refusalMenuItem.isHidden = true
            return
        }
        refusalMenuItem.title = "⚠️ \(notice)"
        refusalMenuItem.isHidden = false
    }

    private func statusText() -> String {
        if !service.isEnabled {
            return "Status: Disabled"
        }
        return service.hasExternalDisplay
            ? "Status: External monitor connected"
            : "Status: Built-in display only"
    }

    /// Draws a menu bar icon showing dock position and visibility.
    /// - `position`: which edge the dock bar is drawn on
    /// - `dockVisible: true` → monitor with dock bar on the given edge
    /// - `dockVisible: false` → monitor outline only (autohide on)
    private func makeIcon(position: DockPosition, dockVisible: Bool) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let rect = NSRect(x: 1, y: 2, width: size - 2, height: size - 4)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.black.setStroke()
            path.lineWidth = 1.2
            path.stroke()

            if dockVisible {
                NSColor.black.setFill()

                switch position {
                case .bottom:
                    let barRect = NSRect(x: 3, y: 3.5, width: size - 6, height: 3)
                    NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
                    NSColor.white.setFill()
                    for i in 0..<3 {
                        let dotRect = NSRect(x: 5.0 + CGFloat(i) * 3.5, y: 4.0, width: 2, height: 2)
                        NSBezierPath(ovalIn: dotRect).fill()
                    }

                case .left:
                    let barRect = NSRect(x: 2.5, y: 4, width: 3, height: size - 8)
                    NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
                    NSColor.white.setFill()
                    for i in 0..<3 {
                        let dotRect = NSRect(x: 3.0, y: 5.0 + CGFloat(i) * 3.0, width: 2, height: 2)
                        NSBezierPath(ovalIn: dotRect).fill()
                    }

                case .right:
                    let barRect = NSRect(x: size - 5.5, y: 4, width: 3, height: size - 8)
                    NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
                    NSColor.white.setFill()
                    for i in 0..<3 {
                        let dotRect = NSRect(x: size - 5.0, y: 5.0 + CGFloat(i) * 3.0, width: 2, height: 2)
                        NSBezierPath(ovalIn: dotRect).fill()
                    }
                }
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    /// Update menu item state each time the menu is opened.
    func menuNeedsUpdate(_ menu: NSMenu) {
        statusMenuItem.title = statusText()
        toggleMenuItem.title = service.isEnabled ? "Disable" : "Enable"
        dockVisibilityMenuItem.title = dockVisibilityTitle()
        applyDockVisibilityAppearance()
        updateRefusalNotice()
        updateActionAvailability()
    }
}

// MARK: - SmartDockServiceDelegate

extension StatusBarController: SmartDockServiceDelegate {
    func serviceDidUpdateState(_ service: SmartDockService, hasExternal: Bool) {
        updateUI()
    }
}

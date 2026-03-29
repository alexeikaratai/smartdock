import Cocoa
import SmartDockCore

/// Menu bar icon controller.
/// Shows current state and allows service management.
@MainActor
final class StatusBarController: NSObject {

    private var statusItem: NSStatusItem!
    private let service: SmartDockService
    private lazy var settingsWindow = SettingsWindow(service: service)

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

    // MARK: - Init

    init(service: SmartDockService) {
        self.service = service
        super.init()
        setupStatusItem()
        service.delegate = self
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let config = service.currentConfig
            button.image = iconCache[config.position]?[!config.autohide]
                ?? iconCache[.bottom]?[true]
            button.toolTip = "SmartDock"
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Title + version
        let version = Bundle.main.shortVersion
        let headerItem = NSMenuItem(title: "SmartDock v\(version)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        ]
        headerItem.attributedTitle = NSAttributedString(string: "SmartDock v\(version)", attributes: attrs)
        menu.addItem(headerItem)

        // Status
        statusMenuItem = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // Enable/disable
        toggleMenuItem = NSMenuItem(
            title: service.isEnabled ? "Disable" : "Enable",
            action: #selector(toggleService),
            keyEquivalent: "e"
        )
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        // Forced refresh
        let refreshItem = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Exit
        let quitItem = NSMenuItem(
            title: "Quit SmartDock",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
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

    func showSettings() {
        settingsWindow.show()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func quit() {
        service.stop()
        NSApp.terminate(nil)
    }

    // MARK: - UI Updates

    private func updateUI() {
        statusMenuItem.title = statusText()
        toggleMenuItem.title = service.isEnabled ? "Disable" : "Enable"

        if let button = statusItem.button {
            // Use our saved config, not readSystemConfig() — the system config can
            // be in a transient state during fullscreen or dock transitions.
            let config = service.currentConfig
            button.image = iconCache[config.position]?[!config.autohide]
                ?? iconCache[.bottom]?[true]
        }
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
    }
}

// MARK: - SmartDockServiceDelegate

extension StatusBarController: SmartDockServiceDelegate {
    func serviceDidUpdateState(_ service: SmartDockService, hasExternal: Bool) {
        updateUI()
    }
}

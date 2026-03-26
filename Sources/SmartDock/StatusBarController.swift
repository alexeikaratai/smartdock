import Cocoa
import SmartDockCore

/// Menu bar icon controller.
/// Shows current state and allows service management.
@MainActor
final class StatusBarController: NSObject {

    private var statusItem: NSStatusItem!
    private let service: SmartDockService
    private lazy var settingsWindow = SettingsWindow(service: service)

    // Cached icon — created once, reused on every state update
    private lazy var cachedIcon: NSImage = makeIcon()

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
            button.image = cachedIcon
            button.toolTip = "SmartDock"
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Title + version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
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

    @objc private func openSettings() {
        settingsWindow.show()
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
            button.image = cachedIcon
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

    /// Generates the menu bar icon.
    /// Tries SF Symbol first, falls back to a custom drawn icon.
    private func makeIcon() -> NSImage {
        // Try SF Symbol first
        if let symbol = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "SmartDock") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let configured = symbol.withSymbolConfiguration(config) ?? symbol
            configured.isTemplate = true
            return configured
        }

        // Fallback: draw a dock bar icon programmatically
        return drawFallbackIcon()
    }

    /// Programmatic dock icon — a rectangle with dots at the bottom.
    /// Used when SF Symbols are unavailable.
    private func drawFallbackIcon() -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let rect = NSRect(x: 1, y: 2, width: size - 2, height: size - 4)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.black.setStroke()
            path.lineWidth = 1.2
            path.stroke()

            // Bottom dock bar
            let barY: CGFloat = 3.5
            let barRect = NSRect(x: 3, y: barY, width: size - 6, height: 3)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1)
            NSColor.black.setFill()
            barPath.fill()

            // Dots on the bar
            for i in 0..<3 {
                let dotX = 5.0 + CGFloat(i) * 3.5
                let dotRect = NSRect(x: dotX, y: barY + 0.5, width: 2, height: 2)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
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

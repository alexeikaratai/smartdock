import Cocoa
import SmartDockCore

/// Menu bar icon controller.
/// Shows current state and allows service management.
@MainActor
public final class StatusBarController: NSObject {

    var statusItem: NSStatusItem!  // internal so a test can read the icon and tooltip
    private let service: SmartDockService
    private let hotkeyManager: HotkeyManager
    lazy var settingsWindow = SettingsWindow(service: service, hotkeyManager: hotkeyManager, prefs: prefs)
    private let prefs: UserPreferences

    // Cached icons: [position][visible/hidden]
    lazy var iconCache: [DockPosition: [Bool: NSImage]] = {
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
    // Internal rather than private so a test can read the menu back — titles,
    // checkmarks, enabled state — and fire an item's action.
    var statusMenuItem: NSMenuItem!
    var toggleMenuItem: NSMenuItem!
    var dockVisibilityMenuItem: NSMenuItem!
    var refusalMenuItem: NSMenuItem!
    var refreshMenuItem: NSMenuItem!
    var profileMenuItems: [DockProfile: NSMenuItem] = [:]
    var positionMenuItem: NSMenuItem!
    var positionMenuItems: [DockPosition: NSMenuItem] = [:]

    // MARK: - Init

    public init(service: SmartDockService, hotkeyManager: HotkeyManager, prefs: UserPreferences = .shared) {
        self.service = service
        self.hotkeyManager = hotkeyManager
        self.prefs = prefs
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
        setTitle(toggleMenuItem.title, symbol: Symbol.toggle, on: toggleMenuItem)
        menu.addItem(toggleMenuItem)

        // Forced refresh
        refreshMenuItem = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refreshMenuItem.target = self
        setTitle("Refresh Now", symbol: Symbol.refresh, on: refreshMenuItem)
        menu.addItem(refreshMenuItem)

        menu.addItem(.separator())

        // Which profile is in force. A checkmark marks the applied one; picking the
        // other applies it on request, exactly as the hotkey or a `smartdock://`
        // URL would — same `HotkeyAction`, same path.
        for profile in DockProfile.allCases {
            let item = NSMenuItem(
                title: profile.displayName,
                action: #selector(selectProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = profile
            setTitle(
                profile.displayName,
                symbol: profile == .external ? Symbol.external : Symbol.builtin,
                on: item)
            profileMenuItems[profile] = item
            menu.addItem(item)
        }

        // Edits to the profile in force: position and visibility. Both write the
        // stored profile and apply at once — there is no draft here, unlike the
        // Dock tab in Settings.
        positionMenuItem = NSMenuItem(title: "Dock Position", action: nil, keyEquivalent: "")
        setTitle("Dock Position", symbol: Symbol.position, on: positionMenuItem)
        let positionMenu = NSMenu()
        positionMenu.autoenablesItems = false
        for position in DockPosition.allCases {
            let item = NSMenuItem(
                title: position.displayName,
                action: #selector(selectPosition(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = position
            positionMenuItems[position] = item
            positionMenu.addItem(item)
        }
        positionMenuItem.submenu = positionMenu
        menu.addItem(positionMenuItem)

        // Hide/show the Dock. Title and icon follow the Dock's actual state, which
        // is why they are refreshed every time the menu opens rather than set once.
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
        // Left bare on purpose, title and all. macOS decorates the item it recognises
        // as the app's settings with a gear of its own — measured by taking ours away
        // and watching a gear remain — so giving it one made the row show two. It draws
        // that gear in the image column, which shifts the words along by about as much
        // as our in-title icon does, so the row lines up with the rest on its own; a
        // spacer of ours on top of it pushed the words a further 40pt to the right.
        menu.addItem(settingsItem)

        // Shortcuts
        let shortcutsItem = NSMenuItem(
            title: "Shortcuts…",
            action: #selector(openShortcuts),
            keyEquivalent: ""
        )
        shortcutsItem.target = self
        setTitle(shortcutsItem.title, symbol: Symbol.shortcuts, on: shortcutsItem)
        menu.addItem(shortcutsItem)

        // About
        let aboutItem = NSMenuItem(
            title: "About SmartDock",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        setTitle(aboutItem.title, symbol: Symbol.about, on: aboutItem)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        // Exit
        let quitItem = NSMenuItem(
            title: "Quit SmartDock",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        setTitle(quitItem.title, symbol: Symbol.quit, on: quitItem)
        menu.addItem(quitItem)

        statusItem.menu = menu
        // The items above are built with placeholder state; reflect the service now
        // rather than only on the first open, so the menu is right from the start.
        updateMenuState()
    }

    // MARK: - Menu Item Icons

    /// Symbol names, named once so a title change and its icon cannot drift apart.
    private enum Symbol {
        static let toggle = "power"
        static let refresh = "arrow.clockwise"
        static let external = "display.2"
        static let builtin = "laptopcomputer"
        static let position = "rectangle.bottomthird.inset.filled"
        static let settings = "gearshape"
        static let shortcuts = "keyboard"
        static let about = "info.circle"
        static let quit = "xmark.circle"
    }

    /// Gives an item a title with its icon in front of it.
    ///
    /// The icon goes **inside** the attributed title rather than into
    /// `NSMenuItem.image`, because macOS 26 draws no image in a status menu at all —
    /// measured against a thirty-line app that set nothing but `image`, and against the
    /// same app setting an attachment, which did draw. The attachment keeps what the
    /// image gave: it whitens under the highlight and greys out with a disabled item,
    /// both checked on the running menu.
    ///
    /// `title` is set too and stays the plain wording — it is what the tests read and
    /// what the menu falls back to. Every later change of wording comes back through
    /// here: setting `title` alone would leave the old attributed string in place and
    /// the item would go on displaying the previous words.
    private func setTitle(_ title: String, symbol: String, on item: NSMenuItem) {
        item.title = title
        item.attributedTitle = Self.attributedTitle(title, symbol: symbol)
    }

    /// Where the words start, measured from the icon's left edge. Wide enough for the
    /// widest symbol here plus a gap.
    static let textColumn: CGFloat = 26

    /// The height every icon is drawn at; its width follows from its own proportions.
    static let iconHeight: CGFloat = 14

    /// The icon, a tab, then the words.
    ///
    /// The symbol image goes in untouched. Drawing it into a fixed box first — which is
    /// how the icons were first made to line up — rasterises it, and the template mask
    /// does not survive: the glyph then keeps one colour while the row highlights and
    /// the system changes theme around it. Measured by removing the redraw and watching
    /// the icons start following the cursor again.
    ///
    /// So the width is whatever the symbol's proportions give, and a tab stop does the
    /// aligning instead of a uniform box.
    static func attributedTitle(_ title: String, symbol: String) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        {
            // Template, or it follows neither the highlight nor the theme.
            image.isTemplate = true
            let size = image.size
            let width = size.height > 0 ? size.width * (iconHeight / size.height) : iconHeight

            let attachment = NSTextAttachment()
            attachment.image = image
            // Measured against the menu's own text: the glyph sits low otherwise.
            attachment.bounds = CGRect(x: 0, y: -3, width: width, height: iconHeight)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "\t"))
        }

        result.append(NSAttributedString(string: title))

        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: textColumn)]
        result.addAttribute(
            .paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
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

    /// Every item that moves the Dock goes through `HotkeyManager.perform` — the
    /// menu is one more front door onto the path hotkeys, URLs, AppleScript and
    /// Shortcuts share, not a second implementation of any of them.
    @objc private func refresh() {
        hotkeyManager.perform(.refreshNow)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? DockProfile else { return }
        hotkeyManager.perform(HotkeyAction(profile.command))
    }

    /// Position has no hotkey, URL or script command, so it edits the profile in
    /// force directly — through the service, which knows which profile that is.
    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard let position = sender.representedObject as? DockPosition else { return }
        service.updateActiveProfile(service.activeProfileConfig.with(position: position))
    }

    public func showSettings(tab: SettingsWindow.Tab = .dock) {
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
        updateMenuState()

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

    /// Everything in the menu that reflects state, in one place — it is refreshed
    /// both when the service reports a change and each time the menu opens, since
    /// a refusal only becomes known a second after the apply.
    private func updateMenuState() {
        statusMenuItem.title = statusText()
        setTitle(
            service.isEnabled ? "Disable" : "Enable", symbol: Symbol.toggle, on: toggleMenuItem)
        // Title and symbol both change with visibility, so they are set together by
        // `applyDockVisibilityAppearance` — assigning `title` here as well would put a
        // plain string back over the one carrying the icon.
        applyDockVisibilityAppearance()
        for (profile, item) in profileMenuItems {
            item.state = profile == service.activeProfile ? .on : .off
        }
        for (position, item) in positionMenuItems {
            item.state = position == service.activeProfileConfig.position ? .on : .off
        }
        updateRefusalNotice()
        updateActionAvailability()
    }

    private func tooltipText() -> String {
        let profile = service.activeProfile.displayName
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
        service.activeProfileConfig.autohide ? "Show Dock" : "Hide Dock"
    }

    private func applyDockVisibilityAppearance() {
        let symbol = service.activeProfileConfig.autohide ? "eye" : "eye.slash"
        setTitle(dockVisibilityTitle(), symbol: symbol, on: dockVisibilityMenuItem)
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
        positionMenuItem.isEnabled = service.isEnabled
        for item in profileMenuItems.values { item.isEnabled = service.isEnabled }
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
        return "Status: \(service.activeProfileDescription)"
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
    public func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenuState()
    }
}

// MARK: - SmartDockServiceDelegate

extension StatusBarController: SmartDockServiceDelegate {
    public func serviceDidUpdateState(_ service: SmartDockService, hasExternal: Bool) {
        updateUI()
    }
}

// MARK: - Menu Item Wording

extension NSMenuItem {

    /// What the item actually displays, without the icon carried alongside it.
    ///
    /// Reads the attributed title first, because that is what the menu draws and the
    /// two can disagree: assigning `title` leaves an existing `attributedTitle` in
    /// place untouched, so the property says one thing while the menu shows another —
    /// measured. Setting `attributedTitle` does overwrite `title`, with the attributed
    /// string's plain text, where a text attachment contributes `U+FFFC` and its
    /// spacing. Anything asking "what does this item say" reads this, never `title`.
    var wording: String {
        let shown = attributedTitle?.string ?? title
        guard let marker = shown.lastIndex(of: "\u{FFFC}") else { return shown }
        return String(shown[shown.index(after: marker)...])
            .trimmingCharacters(in: .whitespaces)
    }
}

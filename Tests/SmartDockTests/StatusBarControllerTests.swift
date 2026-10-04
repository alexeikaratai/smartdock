import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

/// The menu is the app's face. These read it back the way a person sees it —
/// titles, checkmarks, greyed items — and fire its items the way `NSMenu` would,
/// through each item's target and action.
@Suite("Status bar menu")
@MainActor
struct StatusBarControllerTests {

    // MARK: - Fixture

    @MainActor
    private struct Fixture {
        let scratch = ScratchPreferences()
        let monitor = MockDisplayMonitor()
        let dock = MockDockController()
        let service: SmartDockService
        let hotkeys: HotkeyManager
        let menu: StatusBarController

        init(externalCount: Int = 1, started: Bool = true) {
            scratch.prefs.externalConfig = DockConfiguration(autohide: false, position: .bottom)
            scratch.prefs.builtinConfig = DockConfiguration(autohide: true, position: .left)
            monitor.mockExternalCount = externalCount
            service = SmartDockService(displayMonitor: monitor, dockController: dock, prefs: scratch.prefs)
            if started { service.start() }
            hotkeys = HotkeyManager(
                service: service, prefs: scratch.prefs,
                // Private: the workspace centre is process-wide, and a real activation
                // mid-suite would have this manager install real event monitors.
                workspaceEvents: NotificationCenter())
            menu = StatusBarController(service: service, hotkeyManager: hotkeys, prefs: scratch.prefs)
        }

        /// Fires an item exactly as AppKit does when it is clicked.
        func click(_ item: NSMenuItem) {
            _ = item.target?.perform(item.action!, with: item)
        }
    }

    // MARK: - What the Menu Shows

    @Test func theStatusLineNamesTheProfileInForce() {
        let f = Fixture(externalCount: 1)

        #expect(f.menu.statusMenuItem.wording == "Status: External monitor connected")

        f.service.applyProfile(.builtin)
        f.menu.menuNeedsUpdate(NSMenu())

        #expect(f.menu.statusMenuItem.wording == "Status: Built-in profile · external monitor connected")
    }

    @Test func theCheckmarkSitsOnTheProfileInForce() {
        let f = Fixture(externalCount: 1)
        #expect(f.menu.profileMenuItems[.external]?.state == .on)
        #expect(f.menu.profileMenuItems[.builtin]?.state == .off)

        f.service.applyProfile(.builtin)

        #expect(f.menu.profileMenuItems[.builtin]?.state == .on, "the delegate callback moves the mark")
        #expect(f.menu.profileMenuItems[.external]?.state == .off)
    }

    @Test func thePositionSubmenuMarksTheCurrentPosition() {
        let f = Fixture(externalCount: 0)  // built-in profile: left

        #expect(f.menu.positionMenuItems[.left]?.state == .on)
        #expect(f.menu.positionMenuItems[.bottom]?.state == .off)
        #expect(f.menu.positionMenuItems[.right]?.state == .off)
    }

    /// Names what the click will *do*, not what the state is.
    @Test func theVisibilityItemNamesTheAction() {
        let external = Fixture(externalCount: 1)  // visible
        #expect(external.menu.dockVisibilityMenuItem.wording == "Hide Dock")

        let builtin = Fixture(externalCount: 0)  // hidden
        #expect(builtin.menu.dockVisibilityMenuItem.wording == "Show Dock")
    }

    @Test func aDisabledServiceGreysEverythingThatMovesTheDock() {
        let f = Fixture(started: false)

        #expect(f.menu.statusMenuItem.wording == "Status: Disabled")
        #expect(f.menu.toggleMenuItem.wording == "Enable")
        #expect(!f.menu.refreshMenuItem.isEnabled)
        #expect(!f.menu.dockVisibilityMenuItem.isEnabled)
        #expect(!f.menu.positionMenuItem.isEnabled)
        for item in f.menu.profileMenuItems.values { #expect(!item.isEnabled) }
    }

    @Test func aRefusalIsShownUnderTheStatusLine() {
        // The Dock is visible (external profile); asking it to hide is a real change,
        // and this is the one macOS declines while an app is fullscreen.
        let f = Fixture(externalCount: 1)
        #expect(f.menu.refusalMenuItem.isHidden, "Nothing refused yet")

        f.dock.mockRejectedProperties = [.autohide]
        f.dock.apply(f.scratch.prefs.externalConfig.with(autohide: true))
        f.menu.menuNeedsUpdate(NSMenu())

        #expect(!f.menu.refusalMenuItem.isHidden)
        #expect(f.menu.refusalMenuItem.wording.contains("auto-hide"))
    }

    /// After a refusal the item names what the *profile* asks for, so pressing it
    /// twice returns to the start; the refusal line right below says macOS declined,
    /// and the menu bar icon still draws the Dock as it really is.
    @Test func theVisibilityItemFollowsTheProfileEvenWhenTheDockRefuses() {
        let f = Fixture(externalCount: 1)
        f.dock.mockRejectedProperties = [.autohide]
        #expect(f.menu.dockVisibilityMenuItem.wording == "Hide Dock")

        f.click(f.menu.dockVisibilityMenuItem)

        #expect(f.scratch.prefs.externalConfig.autohide, "the profile asks to hide")
        #expect(!f.service.currentConfig.autohide, "the Dock did not")
        #expect(f.menu.dockVisibilityMenuItem.wording == "Show Dock", "the item offers the way back")
        #expect(!f.menu.refusalMenuItem.isHidden, "and says why the Dock has not moved")
    }

    /// Same rule for the position submenu: the tick marks the chosen position, not
    /// whichever one the Dock is sitting at after refusing to move.
    @Test func thePositionTickFollowsTheProfileEvenWhenTheDockRefuses() throws {
        let f = Fixture(externalCount: 1)
        f.dock.mockRejectedProperties = [.position]

        f.click(try #require(f.menu.positionMenuItems[.right]))

        #expect(f.scratch.prefs.externalConfig.position == .right)
        #expect(f.service.currentConfig.position == .bottom, "the Dock stayed put")
        #expect(f.menu.positionMenuItems[.right]?.state == .on, "the tick follows the choice")
        #expect(f.menu.positionMenuItems[.bottom]?.state == .off)
    }

    /// Every item that had an icon still carries one, and carries it where macOS 26
    /// will actually draw it: inside the attributed title, not in `NSMenuItem.image`,
    /// which that release ignores in a status menu. Nothing failed when the icons
    /// vanished — the images were still being set, just never rendered.
    @Test func everyIconBearingItemCarriesItsIconInTheTitle() throws {
        let f = Fixture(externalCount: 1)
        var items: [NSMenuItem] = [
            f.menu.toggleMenuItem, f.menu.refreshMenuItem, f.menu.positionMenuItem,
            f.menu.dockVisibilityMenuItem,
        ]
        items.append(contentsOf: f.menu.profileMenuItems.values)

        for item in items {
            let attributed = try #require(item.attributedTitle, "\(item.wording) has no icon")
            #expect(
                attributed.string.contains("\u{FFFC}"),
                "\(item.wording) carries no image attachment")
            #expect(!item.wording.isEmpty, "\(item.wording) lost its words")
        }
    }

    /// The icon survives a change of wording. It lives in the title, so a plain
    /// `title =` anywhere would drop it — and the item would keep the old words too.
    @Test func theIconSurvivesTheTitleChanging() {
        let f = Fixture(externalCount: 1)
        #expect(f.menu.toggleMenuItem.wording == "Disable")

        f.click(f.menu.toggleMenuItem)

        // Read from what the menu draws, not from `title`: assigning `title` alone
        // leaves the attributed string — icon *and* old words — on screen untouched.
        #expect(f.menu.toggleMenuItem.wording == "Enable", "the words follow the state")
        #expect(
            f.menu.toggleMenuItem.attributedTitle?.string.contains("\u{FFFC}") == true,
            "the icon was dropped when the wording changed")
    }

    /// The settings item must stay bare: macOS draws a gear on it by itself, and ours
    /// made two. Found by eye, so it is pinned here — nothing else would catch it.
    @Test func theSettingsItemCarriesNoIconOfOurs() throws {
        let f = Fixture(externalCount: 1)
        let menu = try #require(f.menu.statusItem.menu)
        let settings = try #require(
            menu.items.first { $0.wording.hasPrefix("Settings") }, "no settings item")

        #expect(
            settings.attributedTitle == nil,
            "macOS draws its own gear here; anything of ours makes two icons or shifts the words")
        #expect(settings.wording == "Settings…")
    }

    /// Icons keep their own proportions. They were drawn into one fixed box at first,
    /// which lined them up and squashed the wide ones — a laptop and a rectangle came
    /// out visibly stretched. Widths differ now because each follows its symbol; the
    /// column is held by a tab stop instead.
    @Test func iconsAreNotSquashedIntoAUniformBox() throws {
        let f = Fixture(externalCount: 1)
        var widths: Set<CGFloat> = []

        let items: [NSMenuItem] = [
            f.menu.toggleMenuItem, f.menu.positionMenuItem, f.menu.dockVisibilityMenuItem,
        ]
        for item in items {
            let attributed = try #require(item.attributedTitle)
            let attachment = try #require(
                attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
                "\(item.wording) has no icon")
            #expect(
                attachment.image?.isTemplate == true,
                "\(item.wording): a non-template image follows neither highlight nor theme")
            widths.insert(attachment.bounds.width)
        }

        #expect(widths.count > 1, "every icon got the same width — they are being stretched")
    }

    /// The words line up whatever the icon's width, which is what the tab stop is for.
    @Test func theWordsStartAtOneColumn() throws {
        let f = Fixture(externalCount: 1)
        let attributed = try #require(f.menu.toggleMenuItem.attributedTitle)
        let style = try #require(
            attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle)

        #expect(style.tabStops.count == 1)
        #expect(style.tabStops.first?.location == StatusBarController.textColumn)
    }

    // MARK: - What the Items Do

    @Test func theToggleItemStopsAndStartsTheService() {
        let f = Fixture()
        #expect(f.service.isEnabled)

        f.click(f.menu.toggleMenuItem)
        #expect(!f.service.isEnabled)
        #expect(f.menu.toggleMenuItem.wording == "Enable")

        f.click(f.menu.toggleMenuItem)
        #expect(f.service.isEnabled)
        #expect(f.menu.toggleMenuItem.wording == "Disable")
    }

    @Test func refreshGoesThroughTheHotkeyPath() {
        let f = Fixture()
        let applies = f.dock.applyCallCount

        f.click(f.menu.refreshMenuItem)

        #expect(f.dock.applyCallCount == applies + 1)
    }

    @Test func aProfileItemAppliesThatProfileOnRequest() throws {
        let f = Fixture(externalCount: 1)

        f.click(try #require(f.menu.profileMenuItems[.builtin]))

        #expect(f.service.activeProfile == .builtin)
        #expect(f.dock.lastAppliedConfig?.autohide == true, "the built-in profile hides the Dock")
    }

    /// Position edits the profile in force and applies at once — no draft here.
    @Test func aPositionItemMovesTheDockAndStoresIt() throws {
        let f = Fixture(externalCount: 1)

        f.click(try #require(f.menu.positionMenuItems[.right]))

        #expect(f.dock.lastAppliedConfig?.position == .right)
        #expect(f.scratch.prefs.externalConfig.position == .right, "stored in the profile in force")
        #expect(f.menu.positionMenuItems[.right]?.state == .on)
    }

    @Test func theVisibilityItemTogglesAutoHideOnTheProfileInForce() {
        let f = Fixture(externalCount: 1)

        f.click(f.menu.dockVisibilityMenuItem)

        #expect(f.dock.lastAppliedConfig?.autohide == true)
        #expect(f.scratch.prefs.externalConfig.autohide, "written to the external profile, which is in force")
        #expect(f.menu.dockVisibilityMenuItem.wording == "Show Dock")
    }

    // MARK: - Icon & Windows

    /// One icon per position and visibility, drawn once and reused. Rendering each
    /// runs its drawing handler — an `NSImage` with a handler draws lazily.
    @Test func everyMenuBarIconRenders() {
        let f = Fixture()

        for position in DockPosition.allCases {
            for visible in [true, false] {
                let image = f.menu.iconCache[position]?[visible]
                #expect(image?.tiffRepresentation != nil, "\(position) \(visible ? "visible" : "hidden")")
            }
        }
        #expect(f.menu.statusItem.button?.image?.isTemplate == true)
    }

    @Test func theTooltipNamesProfileAndDock() {
        let f = Fixture(externalCount: 0)

        #expect(f.menu.statusItem.button?.toolTip == "SmartDock — Built-in Display\nDock: Left, hidden")
    }

    @Test func settingsItemsOpenTheWindowOnTheirTab() {
        _ = NSApplication.shared
        let f = Fixture()

        f.menu.showSettings(tab: .about)

        #expect(f.menu.settingsWindow.window?.isVisible == true)
        #expect(f.menu.settingsWindow.currentTab == .about)
        f.menu.settingsWindow.window?.close()
    }
}

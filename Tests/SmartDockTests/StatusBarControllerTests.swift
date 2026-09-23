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
            hotkeys = HotkeyManager(service: service, prefs: scratch.prefs)
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

        #expect(f.menu.statusMenuItem.title == "Status: External monitor connected")

        f.service.applyProfile(.builtin)
        f.menu.menuNeedsUpdate(NSMenu())

        #expect(f.menu.statusMenuItem.title == "Status: Built-in profile · external monitor connected")
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
        #expect(external.menu.dockVisibilityMenuItem.title == "Hide Dock")

        let builtin = Fixture(externalCount: 0)  // hidden
        #expect(builtin.menu.dockVisibilityMenuItem.title == "Show Dock")
    }

    @Test func aDisabledServiceGreysEverythingThatMovesTheDock() {
        let f = Fixture(started: false)

        #expect(f.menu.statusMenuItem.title == "Status: Disabled")
        #expect(f.menu.toggleMenuItem.title == "Enable")
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
        #expect(f.menu.refusalMenuItem.title.contains("auto-hide"))
    }

    /// After a refusal the item names what the *profile* asks for, so pressing it
    /// twice returns to the start; the refusal line right below says macOS declined,
    /// and the menu bar icon still draws the Dock as it really is.
    @Test func theVisibilityItemFollowsTheProfileEvenWhenTheDockRefuses() {
        let f = Fixture(externalCount: 1)
        f.dock.mockRejectedProperties = [.autohide]
        #expect(f.menu.dockVisibilityMenuItem.title == "Hide Dock")

        f.click(f.menu.dockVisibilityMenuItem)

        #expect(f.scratch.prefs.externalConfig.autohide, "the profile asks to hide")
        #expect(!f.service.currentConfig.autohide, "the Dock did not")
        #expect(f.menu.dockVisibilityMenuItem.title == "Show Dock", "the item offers the way back")
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

    // MARK: - What the Items Do

    @Test func theToggleItemStopsAndStartsTheService() {
        let f = Fixture()
        #expect(f.service.isEnabled)

        f.click(f.menu.toggleMenuItem)
        #expect(!f.service.isEnabled)
        #expect(f.menu.toggleMenuItem.title == "Enable")

        f.click(f.menu.toggleMenuItem)
        #expect(f.service.isEnabled)
        #expect(f.menu.toggleMenuItem.title == "Disable")
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
        #expect(f.menu.dockVisibilityMenuItem.title == "Show Dock")
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

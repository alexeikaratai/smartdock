import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

/// The default window size is a measured number, and every control added to the Dock
/// tab invalidates it. It was written down in a comment and checked by eye: 552 before
/// the indicator and minimize-into-app toggles, 600 after, and nothing failed when the
/// menu bar checkbox made it wrong again. The promise is that no tab scrolls at the
/// default size — so that is what gets asserted, rather than the number itself.
@Suite("Settings window size")
@MainActor
struct SettingsWindowSizeTests {

    /// A shown settings window on the Dock tab, sized as asked.
    private func showDockTab(at size: NSSize) throws -> (SettingsWindow, NSWindow, NSScrollView) {
        _ = NSApplication.shared
        let scratch = ScratchPreferences()
        let monitor = MockDisplayMonitor()
        let service = SmartDockService(
            displayMonitor: monitor, dockController: MockDockController(), prefs: scratch.prefs)
        let hotkeys = HotkeyManager(
            service: service, prefs: scratch.prefs,
            // Private: the workspace centre is process-wide, and a real activation
            // mid-suite would have this manager install real event monitors.
            workspaceEvents: NotificationCenter())
        let settings = SettingsWindow(
            service: service, hotkeyManager: hotkeys, prefs: scratch.prefs,
            decideDraft: { _ in .discard })

        settings.show(tab: .dock)
        let window = try #require(settings.window)
        window.setContentSize(size)
        window.layoutIfNeeded()
        return (settings, window, try #require(settings.settingsScroll))
    }

    /// The height outside the scroll view — header and tab control.
    private func chromeHeight(_ window: NSWindow, _ scroll: NSScrollView) throws -> CGFloat {
        let contentView = try #require(window.contentView)
        return contentView.bounds.height - scroll.contentView.bounds.height
    }

    /// What the fit check rests on: the header and tab control are a fixed height, so a
    /// window the server refused to make as large as asked still yields the same answer.
    /// Without this the fit test measured the realised window and passed on a desktop
    /// while failing on a CI runner, which clamped the content to 554pt.
    @Test func theChromeHeightDoesNotDependOnTheWindowSize() throws {
        let (big, bigWindow, bigScroll) = try showDockTab(at: SettingsWindow.defaultContentSize)
        defer { big.window?.close() }
        let (small, smallWindow, smallScroll) = try showDockTab(
            at: NSSize(width: SettingsWindow.defaultContentSize.width, height: 500))
        defer { small.window?.close() }

        let atDefault = try chromeHeight(bigWindow, bigScroll)
        let atSmall = try chromeHeight(smallWindow, smallScroll)

        #expect(atDefault > 0)
        #expect(
            abs(atDefault - atSmall) < 1,
            "header+tabs measure \(atDefault)pt in a full window and \(atSmall)pt in a squeezed one")
    }

    @Test func theDockTabFitsTheDefaultWindowWithoutScrolling() throws {
        let (settings, window, scroll) = try showDockTab(at: SettingsWindow.defaultContentSize)
        defer { settings.window?.close() }

        let content = try #require(scroll.documentView).fittingSize.height

        // Measured against the size the window *asks* for, not the one it got. A window
        // server can refuse: on a CI runner the content came back 554pt tall however
        // large the window was made, and comparing with the realised height failed there
        // while passing on a desktop. What survives clamping is everything outside the
        // scroll view, which `theChromeHeightDoesNotDependOnTheWindowSize` pins.
        let outside = try chromeHeight(window, scroll)
        let needed = content + outside
        #expect(
            needed <= SettingsWindow.defaultContentSize.height,
            """
            The Dock tab needs \(Int(content.rounded()))pt and the header another \
            \(Int(outside.rounded()))pt, so the window has to be \(Int(needed.rounded()))pt \
            tall — it is \(Int(SettingsWindow.defaultContentSize.height))pt, so the tab \
            scrolls at its default size. Raise `SettingsWindow.defaultContentSize`.
            """)
    }
}

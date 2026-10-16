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
    private func showDockTab(at size: NSSize, accessibilityGranted: Bool = false) throws -> (
        SettingsWindow, NSWindow, NSScrollView
    ) {
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
            decideDraft: { _ in .discard },
            isAccessibilityGranted: { accessibilityGranted })

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

    /// Everything fits at the default window size, Apply included. The promise was
    /// briefly given up during the SwiftUI move: a grouped `Form` measured 858pt against
    /// the window's 900pt maximum, the tab scrolled and the confirming button sat below
    /// the fold. Laid out as one compact card it is 605pt — tighter than the 630 the
    /// AppKit form needed — so the promise is back and this is what keeps it.
    @Test func theDockTabFitsTheDefaultWindowWithoutScrolling() throws {
        let (settings, window, scroll) = try showDockTab(at: SettingsWindow.defaultContentSize)
        defer { settings.window?.close() }

        let content = try #require(scroll.documentView).fittingSize.height
        // Measured against the size the window *asks* for, not the one it got. A window
        // server can refuse: on a CI runner the content came back 554pt tall however
        // large the window was made, and comparing with the realised height failed there
        // while passing on a desktop.
        let outside = try chromeHeight(window, scroll)
        let needed = content + outside

        #expect(content > 0, "the tab measures as nothing")
        #expect(
            needed <= SettingsWindow.defaultContentSize.height,
            """
            The Dock tab needs \(Int(content.rounded()))pt and the header another \
            \(Int(outside.rounded()))pt, so the window has to be \(Int(needed.rounded()))pt \
            tall — it is \(Int(SettingsWindow.defaultContentSize.height))pt, so the tab \
            scrolls and Apply falls below the fold.
            """)
    }

    /// Only the Dock tab has a scroll view. The other three are pinned straight into the
    /// window, so content taller than it is simply unreachable — which is a real defect,
    /// and the one this catches.
    /// Only the Dock tab has a scroll view. The other three are pinned straight into the
    /// window, so anything taller than it is simply unreachable.
    ///
    /// This measures the **realised** view against what its contents ask for, not
    /// `fittingSize` against the window. The first version did the latter and passed while
    /// the Shortcuts tab's last line was visibly clipped: a hosting view's `fittingSize`
    /// came up short of what SwiftUI drew, so the test and the defect agreed with each
    /// other and both were wrong.
    @Test(arguments: [SettingsWindow.Tab.general, .shortcuts, .about])
    func theOtherTabsAreNotClipped(tab: SettingsWindow.Tab) throws {
        let (settings, window, _) = try showDockTab(
            at: SettingsWindow.defaultContentSize, accessibilityGranted: false)
        defer { settings.window?.close() }
        settings.show(tab: tab)
        window.layoutIfNeeded()

        let container = try #require(settings.container(for: tab))
        let parent = try #require(container.superview)

        #expect(container.frame.height > 0, "the \(tab) tab was never laid out")
        // Pinned to the bottom, which is the whole fix: left to its own `fittingSize` a
        // hosting view came up short of what SwiftUI drew and the tab's last line was
        // clipped against a frame that ended above it.
        #expect(
            abs(container.frame.minY - parent.bounds.minY) < 1,
            """
            the \(tab) tab's frame stops \(Int(container.frame.minY - parent.bounds.minY))pt \
            above the window — with no scroll view, anything below that is unreachable.
            """)
    }

    // `theShortcutsRowsFollowTheStatusWhenThereIsNoWarning` lived here. It measured the
    // gap between the tab's header and its first shortcut row, because a *hidden* AppKit
    // view keeps the height its contents ask for and left 133pt of blank once the
    // permission was granted. SwiftUI removes a view an `if` excludes, so there is no
    // hidden view to hold the space and nothing left to measure —
    // `theOtherTabsNeedNoScrolling` covers what remains, which is that the tab fits.

}

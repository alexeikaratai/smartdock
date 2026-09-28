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

    @Test func theDockTabFitsTheDefaultWindowWithoutScrolling() throws {
        _ = NSApplication.shared
        let scratch = ScratchPreferences()
        let monitor = MockDisplayMonitor()
        let service = SmartDockService(
            displayMonitor: monitor, dockController: MockDockController(), prefs: scratch.prefs)
        let hotkeys = HotkeyManager(service: service, prefs: scratch.prefs)
        let settings = SettingsWindow(
            service: service, hotkeyManager: hotkeys, prefs: scratch.prefs,
            decideDraft: { _ in .discard })
        defer { settings.window?.close() }

        settings.show(tab: .dock)
        let window = try #require(settings.window)
        window.setContentSize(SettingsWindow.defaultContentSize)
        window.layoutIfNeeded()

        let scroll = try #require(settings.settingsScroll)
        let content = try #require(scroll.documentView).fittingSize.height
        let visible = scroll.contentView.bounds.height

        #expect(
            content <= visible,
            """
            The Dock tab needs \(Int(content.rounded()))pt but only \(Int(visible.rounded()))pt \
            is visible, so it scrolls at the default size. Raise \
            `SettingsWindow.defaultContentSize` by \(Int((content - visible).rounded()))pt.
            """)
    }
}

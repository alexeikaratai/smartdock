import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

/// Draws the README's screenshot, and asserts nothing.
///
/// It lives here because rendering the real window needs the real view hierarchy, which
/// only the test bundle can build. It is off unless `SHOT_PATH` is set, so an ordinary
/// `swift test` neither runs it nor writes a file:
///
///     SHOT_PATH=assets/settings.png \
///       SHOT_VERSION=$(awk '/^VERSION/ {print $3; exit}' Makefile) \
///       swift test --filter renderTheSettingsWindow
///
/// The point is that re-shooting costs one command. The picture it replaced was taken by
/// hand at 1.8.1 and still showed a three-tab window five versions later, because nothing
/// made it cheap to retake. It draws from a scratch store, so it shows made-up settings
/// rather than those of whoever runs it.
@Suite("Shot tool")
@MainActor
struct ShotTool {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHOT_PATH"] != nil))
    func renderTheSettingsWindow() throws {
        _ = NSApplication.shared

        let scratch = ScratchPreferences()
        scratch.prefs.externalConfig = DockConfiguration(
            autohide: false,
            position: .left,
            iconSize: DockConfiguration.pixelsToScale(48),
            magnification: true,
            magnificationSize: DockConfiguration.pixelsToScale(80),
            minimizeEffect: .genie,
            animatesLaunch: true,
            showsRecents: false,
            showsIndicators: true,
            minimizesToApplication: false)
        scratch.prefs.builtinConfig = DockConfiguration(autohide: true, position: .left)

        let monitor = MockDisplayMonitor()
        monitor.mockExternalCount = 1
        let dock = MockDockController()
        let service = SmartDockService(
            displayMonitor: monitor, dockController: dock, prefs: scratch.prefs)
        service.start()
        let hotkeys = HotkeyManager(service: service, prefs: scratch.prefs)
        let settings = SettingsWindow(
            service: service, hotkeyManager: hotkeys, prefs: scratch.prefs,
            decideDraft: { _ in .discard })

        settings.show(tab: .dock)
        let window = try #require(settings.window)
        window.setContentSize(NSSize(width: 420, height: 720))

        // The header reads `Bundle.main.shortVersion`, and in a test bundle that is the
        // runner's 1.0.0. Put the app's real version back before the picture is taken.
        if let version = ProcessInfo.processInfo.environment["SHOT_VERSION"],
            let content = window.contentView
        {
            retitleVersion(in: content, to: "v\(version) · Made with \u{2764} by Alex Karatai")
        }
        // Key, or the close/minimise buttons draw in their inactive grey.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        window.displayIfNeeded()

        // The theme frame rather than the content view, so the picture carries the
        // window's own chrome — rounded corners and the close/minimise buttons.
        let view = try #require(window.contentView?.superview ?? window.contentView)
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let path = try #require(ProcessInfo.processInfo.environment["SHOT_PATH"])
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(rep.pixelsWide)x\(rep.pixelsHigh) to \(path)")

        window.close()
    }

    /// Finds the byline label by what it says and rewrites it.
    private func retitleVersion(in view: NSView, to text: String) {
        if let field = view as? NSTextField, field.stringValue.contains("Made with") {
            field.stringValue = text
            return
        }
        for subview in view.subviews { retitleVersion(in: subview, to: text) }
    }
}

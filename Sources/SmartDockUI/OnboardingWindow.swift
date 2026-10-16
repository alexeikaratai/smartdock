import Cocoa
import SmartDockCore
import SwiftUI

/// Welcome screen shown once on first launch.
/// Explains what SmartDock does, then opens Settings.
@MainActor
public final class OnboardingWindow: NSObject {

    private let prefs: UserPreferences
    var window: NSWindow?  // internal so a test can reach the button

    /// Callback fired when user clicks "Get Started".
    public var onComplete: (() -> Void)?

    // MARK: - Public

    // MARK: - Init

    public init(prefs: UserPreferences = .shared) {
        self.prefs = prefs
        super.init()
    }

    public func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = makeWindow()
        window = w
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Window Construction

    private func makeWindow() -> NSWindow {
        let (w, contentView) = UI.glassWindow(
            title: "Welcome to SmartDock",
            size: NSSize(width: 400, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView]
        )
        buildUI(in: contentView)
        return w
    }

    // MARK: - UI Construction

    /// The contents are SwiftUI; this type keeps the window, the glass and the flag.
    private func buildUI(in container: NSView) {
        let host = NSHostingView(
            rootView: OnboardingContent(appVersion: Bundle.main.shortVersion) { [weak self] in
                self?.getStarted()
            })
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)

        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: - Actions

    /// Internal rather than private: the button that calls it is SwiftUI and cannot be
    /// clicked from a test, so what the click *does* is what gets tested.
    func getStarted() {
        window?.close()  // windowWillClose sets hasSeenOnboarding = true
        onComplete?()
    }
}

// MARK: - NSWindowDelegate

extension OnboardingWindow: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        // Mark as seen even if user closes via X button
        prefs.hasSeenOnboarding = true
        window = nil
    }
}

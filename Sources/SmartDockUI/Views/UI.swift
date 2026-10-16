import Cocoa

// MARK: - Shared Control Factories

/// Factories for the AppKit constructs repeated across SmartDock's windows.
/// Keeps fonts, Auto Layout flags and the glass material consistent in one place.
@MainActor
enum UI {

    /// Label with Auto Layout enabled and the given font.
    static func label(_ text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        return label
    }

    static func glassWindow(
        title: String,
        size: NSSize,
        styleMask: NSWindow.StyleMask
    ) -> (window: NSWindow, content: NSView) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        let vibrancy = NSVisualEffectView()
        vibrancy.translatesAutoresizingMaskIntoConstraints = false
        // `.windowBackground`, not `.hudWindow`. A HUD material is meant for small
        // floating panels and forces a **vibrant dark** appearance whatever the system
        // is set to. AppKit controls survived that; SwiftUI draws a segmented control's
        // selected chip through the vibrancy, and it washed out to white-on-white — the
        // chosen profile became unreadable. This material follows light and dark, which
        // is also what System Settings uses, and this window is read next to it.
        vibrancy.material = .windowBackground
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = vibrancy
        vibrancy.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: vibrancy.topAnchor),
            content.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor),
        ])

        return (window, content)
    }
}

// MARK: - Bundle Helpers

extension Bundle {
    public var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

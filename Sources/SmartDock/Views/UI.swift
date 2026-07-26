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

    /// Small rounded push button used for secondary actions.
    static func smallButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    /// Checkbox with Auto Layout enabled.
    static func checkbox(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: target, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    /// Continuous slider over the 0.0–1.0 dock size scale.
    static func scaleSlider(value: Double, target: AnyObject, action: Selector) -> NSSlider {
        let slider = NSSlider(value: value, minValue: 0, maxValue: 1, target: target, action: action)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.isContinuous = true
        return slider
    }

    /// Translucent rounded card used to group related controls.
    static func glassCard() -> NSVisualEffectView {
        let card = NSVisualEffectView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.material = .popover
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        return card
    }

    /// The translucent, title-less window chrome shared by SmartDock's windows.
    /// Returns the window together with the content view to build UI into —
    /// the window's own `contentView` is the vibrancy layer behind it.
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
        vibrancy.material = .hudWindow
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

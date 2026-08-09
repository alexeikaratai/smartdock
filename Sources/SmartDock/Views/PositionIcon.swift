import Cocoa
import SmartDockCore

// MARK: - Position Icon

/// Draws the small monitor thumbnails used by the dock position picker
/// and by the Settings header.
///
/// Drawing is pure, so each (position, selected) pair is rendered once and
/// cached for the lifetime of the app.
@MainActor
enum PositionIcon {

    static let size = NSSize(width: 44, height: 32)

    private static var cache: [DockPosition: [Bool: NSImage]] = [:]

    /// Cached icon for the given position in selected or unselected style.
    static func image(for position: DockPosition, selected: Bool) -> NSImage {
        if let cached = cache[position]?[selected] { return cached }
        let image = draw(position: position, selected: selected)
        cache[position, default: [:]][selected] = image
        return image
    }

    // MARK: - Private

    private static func draw(position: DockPosition, selected: Bool) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            let monitorRect = rect.insetBy(dx: 3, dy: 3)
            let accentColor = NSColor.controlAccentColor

            let outline = NSBezierPath(roundedRect: monitorRect, xRadius: 4, yRadius: 4)
            if selected {
                accentColor.withAlphaComponent(0.08).setFill()
                outline.fill()
                accentColor.withAlphaComponent(0.6).setStroke()
            } else {
                NSColor.tertiaryLabelColor.withAlphaComponent(0.5).setStroke()
            }
            outline.lineWidth = 1.2
            outline.stroke()

            let barColor = selected ? accentColor : NSColor.secondaryLabelColor
            let dotColor =
                selected
                ? accentColor.withAlphaComponent(0.5)
                : NSColor.tertiaryLabelColor

            let barRect: NSRect
            switch position {
            case .bottom:
                barRect = NSRect(
                    x: monitorRect.minX + 5, y: monitorRect.maxY - 6,
                    width: monitorRect.width - 10, height: 3.5)
            case .left:
                barRect = NSRect(
                    x: monitorRect.minX + 2, y: monitorRect.minY + 4,
                    width: 3.5, height: monitorRect.height - 8)
            case .right:
                barRect = NSRect(
                    x: monitorRect.maxX - 5.5, y: monitorRect.minY + 4,
                    width: 3.5, height: monitorRect.height - 8)
            }

            barColor.setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5).fill()

            let isHorizontal = position == .bottom
            let dotCount = isHorizontal ? 4 : 3
            let dotSize: CGFloat = 2
            let dotSpacing: CGFloat = isHorizontal ? 4 : 3.5
            let totalSpan = CGFloat(dotCount) * dotSize + CGFloat(dotCount - 1) * dotSpacing

            dotColor.setFill()
            for i in 0..<dotCount {
                let offset = CGFloat(i) * (dotSize + dotSpacing)
                let dotRect: NSRect
                if isHorizontal {
                    let startX = barRect.midX - totalSpan / 2
                    let dotY = barRect.minY + (barRect.height - dotSize) / 2
                    dotRect = NSRect(
                        x: startX + offset, y: dotY,
                        width: dotSize, height: dotSize)
                } else {
                    let dotX = barRect.minX + (barRect.width - dotSize) / 2
                    let startY = barRect.midY - totalSpan / 2
                    dotRect = NSRect(
                        x: dotX, y: startY + offset,
                        width: dotSize, height: dotSize)
                }
                NSBezierPath(roundedRect: dotRect, xRadius: 0.5, yRadius: 0.5).fill()
            }

            return true
        }
    }
}

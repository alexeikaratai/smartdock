#!/usr/bin/env swift
/// Generates SmartDock icon (.icns) — a monitor with a dock bar at the bottom.
/// Uses AppKit — only works on macOS.

import AppKit

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16",        16),
    ("icon_16x16@2x",     32),
    ("icon_32x32",        32),
    ("icon_32x32@2x",     64),
    ("icon_128x128",     128),
    ("icon_128x128@2x",  256),
    ("icon_256x256",     256),
    ("icon_256x256@2x",  512),
    ("icon_512x512",     512),
    ("icon_512x512@2x", 1024),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = size
    let padding = s * 0.1

    // Background — rounded square
    let bgRect = NSRect(x: padding, y: padding, width: s - padding * 2, height: s - padding * 2)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.18, yRadius: s * 0.18)

    // Background gradient
    let gradient = NSGradient(
        starting: NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0),
        ending: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
    )!
    gradient.draw(in: bgPath, angle: -90)

    // Monitor
    let monW = s * 0.52
    let monH = s * 0.36
    let monX = (s - monW) / 2
    let monY = s * 0.38

    let monitorRect = NSRect(x: monX, y: monY, width: monW, height: monH)
    let monitorPath = NSBezierPath(roundedRect: monitorRect, xRadius: s * 0.03, yRadius: s * 0.03)
    NSColor(red: 0.3, green: 0.5, blue: 0.95, alpha: 1.0).setFill()
    monitorPath.fill()

    // Screen (inner)
    let screenInset = s * 0.02
    let screenRect = monitorRect.insetBy(dx: screenInset, dy: screenInset)
    let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: s * 0.015, yRadius: s * 0.015)
    NSColor(red: 0.1, green: 0.12, blue: 0.18, alpha: 1.0).setFill()
    screenPath.fill()

    // Monitor stand
    let standW = s * 0.08
    let standH = s * 0.08
    let standX = (s - standW) / 2
    let standY = monY - standH
    let standRect = NSRect(x: standX, y: standY, width: standW, height: standH)
    NSColor(red: 0.25, green: 0.42, blue: 0.82, alpha: 1.0).setFill()
    ctx.fill(standRect)

    // Base
    let baseW = s * 0.2
    let baseH = s * 0.025
    let baseX = (s - baseW) / 2
    let baseY = standY - baseH
    let baseRect = NSRect(x: baseX, y: baseY, width: baseW, height: baseH)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: s * 0.01, yRadius: s * 0.01)
    NSColor(red: 0.25, green: 0.42, blue: 0.82, alpha: 1.0).setFill()
    basePath.fill()

    // Dock bar at the bottom of the screen
    let dockH = s * 0.035
    let dockW = monW * 0.7
    let dockX = (s - dockW) / 2
    let dockY = monY + screenInset + s * 0.015
    let dockRect = NSRect(x: dockX, y: dockY, width: dockW, height: dockH)
    let dockPath = NSBezierPath(roundedRect: dockRect, xRadius: dockH / 2, yRadius: dockH / 2)
    NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.6).setFill()
    dockPath.fill()

    // Dots on dock bar (icons)
    let dotCount = 5
    let dotSize = dockH * 0.5
    let dotSpacing = dockW / CGFloat(dotCount + 1)
    for i in 1...dotCount {
        let dotX = dockX + dotSpacing * CGFloat(i) - dotSize / 2
        let dotY = dockY + (dockH - dotSize) / 2
        let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 0.8).setFill()
        dotPath.fill()
    }

    image.unlockFocus()
    return image
}

// --- Main ---

let iconsetDir = "/tmp/SmartDock.iconset"
let fm = FileManager.default

// Remove if already exists
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (name, size) in sizes {
    let image = drawIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(name)")
        continue
    }
    let path = "\(iconsetDir)/\(name).png"
    try png.write(to: URL(fileURLWithPath: path))
    print("Generated \(name).png (\(size)×\(size))")
}

// Assemble .icns
let outputPath = fm.currentDirectoryPath + "/Resources/AppIcon.icns"
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir, "-o", outputPath]
try proc.run()
proc.waitUntilExit()

if proc.terminationStatus == 0 {
    print("\n✅ AppIcon.icns created at \(outputPath)")
} else {
    print("\n❌ iconutil failed with status \(proc.terminationStatus)")
}

// Clean up
try? fm.removeItem(atPath: iconsetDir)

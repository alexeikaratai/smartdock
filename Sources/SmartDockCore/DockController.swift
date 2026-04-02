import Foundation

// MARK: - Protocol

/// Managing Dock preferences: autohide, position, icon size, magnification.
@MainActor
public protocol DockControlling {
    /// Current autohide state
    func isAutoHideEnabled() -> Bool

    /// Set the autohide state. Returns true on success.
    @discardableResult
    func setAutoHide(_ enabled: Bool) -> Bool

    /// Apply a full dock configuration. Diff-based — only changes properties that differ from system state.
    /// Uses AppleScript → System Events for immediate dock update.
    @discardableResult
    func apply(_ config: DockConfiguration) -> Bool

    /// Read the current system dock configuration.
    func readSystemConfig() -> DockConfiguration
}

// MARK: - Implementation

/// Manages Dock preferences via AppleScript → System Events.
///
/// Each property is set in its own `tell` block so that a failure in one
/// (e.g. magnification size when magnification is off) does not prevent
/// the others from being applied. This avoids the need for `killall Dock`
/// entirely — System Events tells the Dock to update itself gracefully.
public final class DockController: DockControlling {

    public init() {}

    // MARK: - DockControlling

    public func isAutoHideEnabled() -> Bool {
        readSystemConfig().autohide
    }

    @discardableResult
    public func setAutoHide(_ enabled: Bool) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set autohide to \(enabled)
                end tell
            end tell
            """
        )
    }

    /// Read current dock settings directly from the system.
    /// Creates a fresh UserDefaults instance to avoid stale cached values
    /// after AppleScript changes dock preferences via System Events.
    /// Sizes are returned as 0.0–1.0 scale (converted from pixel tilesize).
    public func readSystemConfig() -> DockConfiguration {
        guard let d = UserDefaults(suiteName: "com.apple.dock") else {
            return DockConfiguration()
        }
        let orientationRaw = d.string(forKey: "orientation") ?? "bottom"
        let tilesize = d.integer(forKey: "tilesize")
        let largesize = d.integer(forKey: "largesize")

        return DockConfiguration(
            autohide: d.bool(forKey: "autohide"),
            position: DockPosition(rawValue: orientationRaw) ?? .bottom,
            iconSize: tilesize > 0 ? DockConfiguration.pixelsToScale(tilesize) : 0.2857,
            magnification: d.bool(forKey: "magnification"),
            magnificationSize: largesize > 0 ? DockConfiguration.pixelsToScale(largesize) : 0.4286
        )
    }

    @discardableResult
    public func apply(_ config: DockConfiguration) -> Bool {
        // Read current system state and only apply properties that differ.
        // Each AppleScript poke can cause the Dock to briefly flash — skipping
        // unchanged properties avoids spurious dock appearances.
        let current = readSystemConfig()

        var allOk = true
        var changed: [String] = []

        if config.position != current.position {
            changed.append("position=\(config.position.rawValue)")
            if !applyPosition(config.position) { allOk = false }
        }

        if config.autohide != current.autohide {
            changed.append("autohide=\(config.autohide)")
            if !applyAutohide(config.autohide) { allOk = false }
        }

        // Tolerance covers 1-pixel rounding difference (~0.009 scale).
        if abs(config.iconSize - current.iconSize) > 0.01 {
            changed.append("size=\(String(format: "%.3f", config.iconSize))")
            if !applyIconSize(config.iconSize) { allOk = false }
        }

        if config.magnification != current.magnification {
            changed.append("magnification=\(config.magnification)")
            if !applyMagnification(config.magnification) { allOk = false }
        }

        if config.magnification && abs(config.magnificationSize - current.magnificationSize) > 0.01 {
            changed.append("magSize=\(String(format: "%.3f", config.magnificationSize))")
            if !applyMagnificationSize(config.magnificationSize) { allOk = false }
        }

        if changed.isEmpty {
            Log.info("Dock config unchanged — skipped AppleScript")
        } else {
            let status = allOk ? "" : " [some failed]"
            Log.info("Dock config applied: \(changed.joined(separator: " "))\(status)")
        }

        return allOk
    }

    // MARK: - Per-Property AppleScript

    private func applyPosition(_ position: DockPosition) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set screen edge to \(position.appleScriptValue)
                end tell
            end tell
            """)
    }

    private func applyAutohide(_ autohide: Bool) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set autohide to \(autohide)
                end tell
            end tell
            """)
    }

    private func applyIconSize(_ scale: Double) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set dock size to \(scale)
                end tell
            end tell
            """)
    }

    private func applyMagnification(_ enabled: Bool) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set magnification to \(enabled)
                end tell
            end tell
            """)
    }

    private func applyMagnificationSize(_ scale: Double) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set magnification size to \(scale)
                end tell
            end tell
            """)
    }

    // MARK: - Private

    @discardableResult
    private func runAppleScript(_ source: String) -> Bool {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error = error {
            Log.error("AppleScript error: \(error[NSAppleScript.errorMessage] ?? "unknown") — script: \(source)")
            return false
        }
        return true
    }
}

// MARK: - Position Helpers

fileprivate extension DockPosition {
    /// Value for AppleScript `screen edge` property
    var appleScriptValue: String {
        switch self {
        case .bottom: return "bottom"
        case .left:   return "left"
        case .right:  return "right"
        }
    }
}

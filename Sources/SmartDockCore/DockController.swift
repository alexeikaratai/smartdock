import Foundation

// MARK: - Protocol

/// Managing Dock preferences: autohide, position, icon size, magnification.
public protocol DockControlling {
    /// Current autohide state
    func isAutoHideEnabled() -> Bool

    /// Set the autohide state. Returns true on success.
    @discardableResult
    func setAutoHide(_ enabled: Bool) -> Bool

    /// Apply a full dock configuration.
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

    /// Dock preferences domain (for reading current config)
    private let dockDefaults: UserDefaults?

    public init() {
        self.dockDefaults = UserDefaults(suiteName: "com.apple.dock")
    }

    // MARK: - DockControlling

    public func isAutoHideEnabled() -> Bool {
        dockDefaults?.bool(forKey: "autohide") ?? false
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
    public func readSystemConfig() -> DockConfiguration {
        guard let d = dockDefaults else { return DockConfiguration() }
        let orientationRaw = d.string(forKey: "orientation") ?? "bottom"
        let tilesize = d.integer(forKey: "tilesize")
        let largesize = d.integer(forKey: "largesize")

        return DockConfiguration(
            autohide: d.bool(forKey: "autohide"),
            position: DockPosition(rawValue: orientationRaw) ?? .bottom,
            iconSize: tilesize > 0 ? tilesize : 48,
            magnification: d.bool(forKey: "magnification"),
            magnificationSize: largesize > 0 ? largesize : 64
        )
    }

    @discardableResult
    public func apply(_ config: DockConfiguration) -> Bool {
        // Each property in its own AppleScript call.
        // System Events updates the Dock gracefully — no killall needed.
        // If one property fails, the others still apply.

        let positionStr = config.position.appleScriptValue
        let dockSize = Self.pixelsToAppleScriptScale(config.iconSize)
        let magSize = Self.pixelsToAppleScriptScale(config.magnificationSize)

        var allOk = true

        // Position — use tell block so multi-word values parse correctly
        if !runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set screen edge to \(positionStr)
                end tell
            end tell
            """) { allOk = false }

        // Autohide
        if !runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set autohide to \(config.autohide)
                end tell
            end tell
            """) { allOk = false }

        // Icon size
        if !runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set dock size to \(dockSize)
                end tell
            end tell
            """) { allOk = false }

        // Magnification on/off
        if !runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set magnification to \(config.magnification)
                end tell
            end tell
            """) { allOk = false }

        // Magnification size
        if config.magnification {
            if !runAppleScript("""
                tell application "System Events"
                    tell dock preferences
                        set magnification size to \(magSize)
                    end tell
                end tell
                """) { allOk = false }
        }

        Log.info("Dock config applied via AppleScript: position=\(config.position.rawValue) " +
                 "autohide=\(config.autohide) size=\(config.iconSize) " +
                 "magnification=\(config.magnification) magSize=\(config.magnificationSize)" +
                 (allOk ? "" : " [some properties failed]"))

        return allOk
    }

    // MARK: - Scale Conversion

    /// Converts pixel size (16–128) to AppleScript dock size scale (0.0–1.0).
    /// System Events uses a normalized float; the actual pixel range is 16–128.
    static func pixelsToAppleScriptScale(_ pixels: Int) -> Double {
        let clamped = Double(Swift.max(16, Swift.min(128, pixels)))
        return (clamped - 16.0) / (128.0 - 16.0)
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

private extension DockPosition {
    /// Value for AppleScript `screen edge` property
    var appleScriptValue: String {
        switch self {
        case .bottom: return "bottom"
        case .left:   return "left"
        case .right:  return "right"
        }
    }
}

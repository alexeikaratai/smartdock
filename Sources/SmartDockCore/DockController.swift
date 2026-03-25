import Foundation

// MARK: - Protocol

/// Managing Dock auto-hide functionality.
public protocol DockControlling {
    /// Current autohide state
    func isAutoHideEnabled() -> Bool

    /// Set the autohide state.
    /// Returns `true` on success.
    @discardableResult
    func setAutoHide(_ enabled: Bool) -> Bool
}

// MARK: - Errors

public enum DockControllerError: Error, CustomStringConvertible {
    case appleScriptFailed(String)
    case preferencesUnavailable

    public var description: String {
        switch self {
        case .appleScriptFailed(let message):
            return "AppleScript error: \(message)"
        case .preferencesUnavailable:
            return "Could not read com.apple.dock preferences"
        }
    }
}

// MARK: - Implementation

/// Manages Dock auto-hide through System Events (AppleScript).
///
/// Why AppleScript instead of `defaults write` + `killall Dock`:
/// - Smooth animation instead of restarting the Dock
/// - Instant application without icon flickering
/// - Same mechanism used by System Preferences
public final class DockController: DockControlling {

    /// Dock preferences domain
    private let dockDefaults: UserDefaults?

    /// Cached compiled AppleScripts.
    /// Compiling NSAppleScript is an expensive operation, so we cache both variants.
    private lazy var showDockScript: NSAppleScript? = {
        compileScript(autoHide: false)
    }()

    private lazy var hideDockScript: NSAppleScript? = {
        compileScript(autoHide: true)
    }()

    public init() {
        self.dockDefaults = UserDefaults(suiteName: "com.apple.dock")
    }

    // MARK: - DockControlling

    public func isAutoHideEnabled() -> Bool {
        dockDefaults?.bool(forKey: "autohide") ?? false
    }

    @discardableResult
    public func setAutoHide(_ enabled: Bool) -> Bool {
        // Don't touch the Dock if it's already in the desired state
        guard isAutoHideEnabled() != enabled else { return true }

        let script = enabled ? hideDockScript : showDockScript

        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)

        if let errorInfo = errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown"
            Log.error("Failed to set dock autohide: \(message)")
            return false
        }

        Log.info("Dock autohide → \(enabled)")
        return true
    }

    // MARK: - Private

    private func compileScript(autoHide: Bool) -> NSAppleScript? {
        let source = """
            tell application "System Events"
                set autohide of dock preferences to \(autoHide)
            end tell
            """
        let script = NSAppleScript(source: source)
        // Compile in advance — executeAndReturnError will be faster
        var compileError: NSDictionary?
        script?.compileAndReturnError(&compileError)
        if let err = compileError {
            Log.error("Failed to compile AppleScript: \(err)")
        }
        return script
    }
}

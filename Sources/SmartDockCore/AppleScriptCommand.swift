import Foundation

// MARK: - Dock Profile

/// The `dock profile` enumeration declared in `Resources/SmartDock.sdef`.
///
/// ```applescript
/// tell application "SmartDock" to switch to external
/// ```
///
/// AppleScript identifies an enumerator by a four-character code rather than by
/// name, so `appleEventCode` and the `code` attribute in the `.sdef` must agree
/// exactly. They are asserted against literal values in `AppleScriptCommandTests`
/// — a typo in either place is otherwise invisible until a user's script silently
/// stops matching.
public enum DockProfile: String, CaseIterable, Sendable {
    case external
    case builtin

    /// Four-character code AppleScript sends for this enumerator.
    /// Mirrors `<enumerator code="...">` in SmartDock.sdef.
    public var appleEventCode: FourCharCode {
        switch self {
        case .external: return Self.packed("Dext")
        case .builtin: return Self.packed("Dblt")
        }
    }

    /// Resolves the enumerator a script sent. Returns `nil` for an unknown code
    /// so the command can report a script error rather than guess a profile.
    public init?(appleEventCode code: FourCharCode) {
        guard let match = Self.allCases.first(where: { $0.appleEventCode == code }) else {
            return nil
        }
        self = match
    }

    /// The command this profile activates.
    ///
    /// Deliberately routed through `URLCommand` rather than defining a parallel
    /// vocabulary: AppleScript, `smartdock://` URLs and global hotkeys then share
    /// one execution path, and none of the three can drift away from the others.
    public var command: URLCommand {
        switch self {
        case .external: return .switchToExternal
        case .builtin: return .switchToBuiltin
        }
    }

    // MARK: - Private

    /// Packs a four-character ASCII string into an `OSType`, big-endian — the
    /// layout Carbon four-char codes have always used.
    private static func packed(_ string: String) -> FourCharCode {
        string.utf8.prefix(4).reduce(into: FourCharCode(0)) { code, byte in
            code = (code << 8) | FourCharCode(byte)
        }
    }
}

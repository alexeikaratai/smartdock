import Foundation

// MARK: - URL Command

/// A command SmartDock accepts over its `smartdock://` URL scheme.
///
/// Lets other tools drive the app without a scripting dictionary:
/// ```
/// open smartdock://refresh
/// open smartdock://switch/external
/// ```
/// Parsing lives here — in the testable core — while execution stays in the app layer.
/// The raw value is the canonical URL path, so the synthesised
/// `init?(rawValue:)` speaks the same vocabulary as `init?(url:)` —
/// no second, divergent way to build a command.
public enum URLCommand: String, CaseIterable, Sendable {
    case refresh = "refresh"
    case switchToExternal = "switch/external"
    case switchToBuiltin = "switch/builtin"
    case toggleAutohide = "toggle-autohide"
    case openSettings = "settings"

    /// URL scheme registered in `Info.plist` under `CFBundleURLTypes`.
    public static let scheme = "smartdock"

    /// The canonical URL that triggers this command, e.g. `smartdock://switch/external`.
    public var url: String {
        "\(Self.scheme)://\(rawValue)"
    }

    /// Parses a `smartdock://` URL. Returns `nil` for a foreign scheme or an
    /// unknown command, so callers can ignore it rather than guess.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }

        // "smartdock://switch/external" arrives as host "switch" + path "/external".
        let segments = ([url.host] + url.pathComponents)
            .compactMap { $0 }
            .filter { $0 != "/" && !$0.isEmpty }
            .map { $0.lowercased() }

        switch segments {
        case ["refresh"]:
            self = .refresh
        case ["switch", "external"]:
            self = .switchToExternal
        // Accept the hyphenated spelling too — it is how the UI labels the mode.
        case ["switch", "builtin"], ["switch", "built-in"]:
            self = .switchToBuiltin
        case ["toggle-autohide"], ["toggle", "autohide"]:
            self = .toggleAutohide
        case ["settings"], ["preferences"]:
            self = .openSettings
        default:
            return nil
        }
    }
}

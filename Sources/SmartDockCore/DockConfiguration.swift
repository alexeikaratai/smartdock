import Foundation

// MARK: - Dock Position

public enum DockPosition: String, CaseIterable, Sendable {
    case bottom
    case left
    case right

    public var displayName: String {
        switch self {
        case .bottom: return "Bottom"
        case .left:   return "Left"
        case .right:  return "Right"
        }
    }
}

// MARK: - Dock Configuration

/// Full set of Dock preferences for a given mode (external / built-in).
public struct DockConfiguration: Equatable, Sendable {
    public let autohide: Bool
    public let position: DockPosition
    public let iconSize: Int          // 16...128, default 48
    public let magnification: Bool
    public let magnificationSize: Int // 16...128, default 64

    public init(
        autohide: Bool = false,
        position: DockPosition = .bottom,
        iconSize: Int = 48,
        magnification: Bool = false,
        magnificationSize: Int = 64
    ) {
        self.autohide = autohide
        self.position = position
        self.iconSize = iconSize.clamped(to: 16...128)
        self.magnification = magnification
        self.magnificationSize = magnificationSize.clamped(to: 16...128)
    }
}

// MARK: - User Preferences

/// Persists user preferences for both modes using UserDefaults.
@MainActor
public final class UserPreferences {

    public static let shared = UserPreferences()

    private let defaults = UserDefaults.standard
    private let prefix = "com.smartdock"

    private init() {}

    // MARK: - External Monitor Config

    public var externalConfig: DockConfiguration {
        get { load(key: "external") ?? DockConfiguration(autohide: false) }
        set { save(newValue, key: "external") }
    }

    // MARK: - Built-in Only Config

    public var builtinConfig: DockConfiguration {
        get { load(key: "builtin") ?? DockConfiguration(autohide: true) }
        set { save(newValue, key: "builtin") }
    }

    // MARK: - Persistence

    private func save(_ config: DockConfiguration, key: String) {
        defaults.set(config.autohide, forKey: "\(prefix).\(key).autohide")
        defaults.set(config.position.rawValue, forKey: "\(prefix).\(key).position")
        defaults.set(config.iconSize, forKey: "\(prefix).\(key).iconSize")
        defaults.set(config.magnification, forKey: "\(prefix).\(key).magnification")
        defaults.set(config.magnificationSize, forKey: "\(prefix).\(key).magnificationSize")
    }

    private func load(key: String) -> DockConfiguration? {
        let autohideKey = "\(prefix).\(key).autohide"
        guard defaults.object(forKey: autohideKey) != nil else { return nil }

        let positionRaw = defaults.string(forKey: "\(prefix).\(key).position") ?? "bottom"
        return DockConfiguration(
            autohide: defaults.bool(forKey: autohideKey),
            position: DockPosition(rawValue: positionRaw) ?? .bottom,
            iconSize: defaults.integer(forKey: "\(prefix).\(key).iconSize").nonZero ?? 48,
            magnification: defaults.bool(forKey: "\(prefix).\(key).magnification"),
            magnificationSize: defaults.integer(forKey: "\(prefix).\(key).magnificationSize").nonZero ?? 64
        )
    }
}

// MARK: - Helpers

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    var nonZero: Int? {
        self != 0 ? self : nil
    }
}

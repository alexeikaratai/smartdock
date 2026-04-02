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
/// Sizes use the same 0.0–1.0 scale as macOS System Events / dock preferences.
/// This avoids pixel→scale→pixel rounding issues.
public struct DockConfiguration: Equatable, Sendable {
    public let autohide: Bool
    public let position: DockPosition
    public let iconSize: Double          // 0.0...1.0, default ~0.29 (48px)
    public let magnification: Bool
    public let magnificationSize: Double // 0.0...1.0, default ~0.43 (64px)

    public init(
        autohide: Bool = false,
        position: DockPosition = .bottom,
        iconSize: Double = 0.2857,
        magnification: Bool = false,
        magnificationSize: Double = 0.4286
    ) {
        self.autohide = autohide
        self.position = position
        self.iconSize = iconSize.clamped(to: 0.0...1.0)
        self.magnification = magnification
        self.magnificationSize = magnificationSize.clamped(to: 0.0...1.0)
    }

    /// Convert pixel value (16–128) to scale (0.0–1.0).
    public static func pixelsToScale(_ pixels: Int) -> Double {
        let clamped = Double(Swift.max(16, Swift.min(128, pixels)))
        return (clamped - 16.0) / (128.0 - 16.0)
    }

    /// Convert scale (0.0–1.0) to approximate pixel value (16–128).
    /// For display purposes only — the canonical value is the scale.
    public static func scaleToPixels(_ scale: Double) -> Int {
        Int((scale * 112.0 + 16.0).rounded())
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

    // MARK: - First Launch

    /// On first launch (no saved preferences), read the current system dock
    /// config and set sensible defaults: external = autohide off, built-in = autohide on.
    /// Other properties (position, size, magnification) are taken from the current system config.
    public func initializeDefaultsIfNeeded(from systemConfig: DockConfiguration) {
        guard !isConfigured else { return }

        externalConfig = DockConfiguration(
            autohide: false,
            position: systemConfig.position,
            iconSize: systemConfig.iconSize,
            magnification: systemConfig.magnification,
            magnificationSize: systemConfig.magnificationSize
        )
        builtinConfig = DockConfiguration(
            autohide: true,
            position: systemConfig.position,
            iconSize: systemConfig.iconSize,
            magnification: systemConfig.magnification,
            magnificationSize: systemConfig.magnificationSize
        )

        Log.info("First launch — initialized defaults from system config: "
                 + "position=\(systemConfig.position.rawValue) size=\(systemConfig.iconSize) "
                 + "(external: autohide=false, builtin: autohide=true)")
    }

    /// Whether any preferences have been saved (either mode).
    public var isConfigured: Bool {
        defaults.object(forKey: "\(prefix).external.autohide") != nil
            || defaults.object(forKey: "\(prefix).builtin.autohide") != nil
    }

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

    // MARK: - Migration

    /// Migrate old integer pixel values to new scale format.
    public func migrateIfNeeded() {
        migrateMode("external")
        migrateMode("builtin")
    }

    private func migrateMode(_ key: String) {
        let sizeKey = "\(prefix).\(key).iconSize"
        let magSizeKey = "\(prefix).\(key).magnificationSize"

        // Old format stored integers > 1. New format stores 0.0–1.0.
        // If value > 1.0, it's old pixel format — convert to scale.
        if let sizeVal = defaults.object(forKey: sizeKey) as? Double, sizeVal > 1.0 {
            defaults.set(DockConfiguration.pixelsToScale(Int(sizeVal)), forKey: sizeKey)
        } else if let sizeVal = defaults.object(forKey: sizeKey) as? Int, sizeVal > 1 {
            defaults.set(DockConfiguration.pixelsToScale(sizeVal), forKey: sizeKey)
        }

        if let magVal = defaults.object(forKey: magSizeKey) as? Double, magVal > 1.0 {
            defaults.set(DockConfiguration.pixelsToScale(Int(magVal)), forKey: magSizeKey)
        } else if let magVal = defaults.object(forKey: magSizeKey) as? Int, magVal > 1 {
            defaults.set(DockConfiguration.pixelsToScale(magVal), forKey: magSizeKey)
        }
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
        let iconSize = defaults.double(forKey: "\(prefix).\(key).iconSize")
        let magSize = defaults.double(forKey: "\(prefix).\(key).magnificationSize")

        return DockConfiguration(
            autohide: defaults.bool(forKey: autohideKey),
            position: DockPosition(rawValue: positionRaw) ?? .bottom,
            iconSize: iconSize > 0 ? iconSize : 0.2857,
            magnification: defaults.bool(forKey: "\(prefix).\(key).magnification"),
            magnificationSize: magSize > 0 ? magSize : 0.4286
        )
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

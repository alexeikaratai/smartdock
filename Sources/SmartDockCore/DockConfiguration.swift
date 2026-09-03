import AppKit
import Foundation

// MARK: - Dock Position

public enum DockPosition: String, CaseIterable, Sendable {
    case bottom
    case left
    case right

    public var displayName: String {
        switch self {
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

// MARK: - Minimize Effect

/// How a window animates as it minimises into the Dock.
///
/// Only the two effects System Events actually exposes. macOS also carries a
/// hidden `suck` effect reachable through `defaults write`, but it is absent from
/// the scripting dictionary — setting it would mean writing the Dock's preferences
/// behind its back and restarting it, which is the one thing this app never does.
public enum MinimizeEffect: String, CaseIterable, Sendable {
    case genie
    case scale

    public var displayName: String {
        switch self {
        case .genie: return "Genie"
        case .scale: return "Scale"
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
    public let iconSize: Double  // 0.0...1.0, default ~0.29 (48px)
    public let magnification: Bool
    public let magnificationSize: Double  // 0.0...1.0, default ~0.43 (64px)
    public let minimizeEffect: MinimizeEffect
    /// "Animate opening applications" — `animate` in System Events, `launchanim`
    /// in `com.apple.dock`. Named as an assertion rather than copying either, since
    /// a bare `animate` says nothing about what is animated.
    public let animatesLaunch: Bool

    public init(
        autohide: Bool = false,
        position: DockPosition = .bottom,
        iconSize: Double = 0.2857,
        magnification: Bool = false,
        magnificationSize: Double = 0.4286,
        minimizeEffect: MinimizeEffect = .genie,
        animatesLaunch: Bool = true
    ) {
        self.autohide = autohide
        self.position = position
        self.iconSize = iconSize.clamped(to: 0.0...1.0)
        self.magnification = magnification
        self.magnificationSize = magnificationSize.clamped(to: 0.0...1.0)
        self.minimizeEffect = minimizeEffect
        self.animatesLaunch = animatesLaunch
    }

    /// A copy with some properties replaced and the rest carried over.
    ///
    /// Exists because rebuilding the struct field by field at a call site silently
    /// drops whatever that site has not heard of yet: the auto-hide toggle did
    /// exactly that to `minimizeEffect` and `animatesLaunch` the day they were
    /// added, resetting both every time someone hid the Dock. Anything omitted here
    /// keeps its current value, so a property added later is preserved by default
    /// instead of being lost by default.
    public func with(
        autohide: Bool? = nil,
        position: DockPosition? = nil,
        iconSize: Double? = nil,
        magnification: Bool? = nil,
        magnificationSize: Double? = nil,
        minimizeEffect: MinimizeEffect? = nil,
        animatesLaunch: Bool? = nil
    ) -> DockConfiguration {
        DockConfiguration(
            autohide: autohide ?? self.autohide,
            position: position ?? self.position,
            iconSize: iconSize ?? self.iconSize,
            magnification: magnification ?? self.magnification,
            magnificationSize: magnificationSize ?? self.magnificationSize,
            minimizeEffect: minimizeEffect ?? self.minimizeEffect,
            animatesLaunch: animatesLaunch ?? self.animatesLaunch
        )
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

    /// How far two size values may drift and still count as the same setting.
    ///
    /// Sizes round-trip through the Dock as integer pixels, so a value written as
    /// 0.2857 reads back slightly different. 0.01 scale ≈ 1px. Defined once because
    /// `approximatelyEquals` and `differences(from:)` must agree exactly — one says
    /// "nothing changed", the other says "nothing to apply", and a mismatch between
    /// them makes the app mistake its own no-op for someone else's edit.
    public static let sizeTolerance = 0.01

    /// Compare with tolerance for size fields.
    /// Used by system sync to detect real changes vs rounding noise.
    public func approximatelyEquals(_ other: DockConfiguration) -> Bool {
        guard autohide == other.autohide,
            position == other.position,
            magnification == other.magnification,
            minimizeEffect == other.minimizeEffect,
            animatesLaunch == other.animatesLaunch,
            abs(iconSize - other.iconSize) <= Self.sizeTolerance
        else { return false }

        // Magnified size is invisible while magnification is off, and `differences`
        // deliberately never applies it then. Comparing it here anyway would report
        // our own no-op as an external change — and the stored profile would be
        // overwritten with whatever the system happened to hold.
        guard magnification else { return true }
        return abs(magnificationSize - other.magnificationSize) <= Self.sizeTolerance
    }
}

// MARK: - Dock Property

/// A single Dock setting that can be pushed to the system.
///
/// Each is applied by its own AppleScript block, so one failing does not stop
/// the others — which is why this is a list of independent properties rather
/// than one all-or-nothing write.
public enum DockProperty: String, CaseIterable, Sendable {
    case position
    case autohide
    case iconSize
    case magnification
    case magnificationSize
    case minimizeEffect
    case animatesLaunch

    /// How to name this setting to a person. The raw values are camelCase keys
    /// meant for logs and diagnostics; `iconSize` in a menu would read as a typo.
    public var displayName: String {
        switch self {
        case .position: return "position"
        case .autohide: return "auto-hide"
        case .iconSize: return "icon size"
        case .magnification: return "magnification"
        case .magnificationSize: return "magnification size"
        case .minimizeEffect: return "minimize effect"
        case .animatesLaunch: return "launch animation"
        }
    }
}

// MARK: - Diffing

public extension DockConfiguration {

    /// The properties of this config that differ from `current`, in the order they
    /// should be applied.
    ///
    /// An empty result means the Dock already matches and no AppleScript needs to
    /// run at all — which is what keeps frequent re-applies (wake, refresh, display
    /// change) from making the Dock flash.
    ///
    /// Kept pure and separate from the AppleScript that carries it out: the decision
    /// of *what* to change is the part with edge cases worth testing, and it cannot
    /// be exercised through a controller that talks to the real System Events.
    func differences(from current: DockConfiguration) -> [DockProperty] {
        var changed: [DockProperty] = []

        if position != current.position { changed.append(.position) }
        if autohide != current.autohide { changed.append(.autohide) }
        if abs(iconSize - current.iconSize) > Self.sizeTolerance { changed.append(.iconSize) }
        if magnification != current.magnification { changed.append(.magnification) }

        // Only meaningful while magnification is on. Setting it otherwise would
        // make the Dock flash for a value the user cannot see.
        if magnification, abs(magnificationSize - current.magnificationSize) > Self.sizeTolerance {
            changed.append(.magnificationSize)
        }

        if minimizeEffect != current.minimizeEffect { changed.append(.minimizeEffect) }
        if animatesLaunch != current.animatesLaunch { changed.append(.animatesLaunch) }

        return changed
    }

    /// The value this config carries for `property`, rendered for logs.
    func describe(_ property: DockProperty) -> String {
        switch property {
        case .position: return "position=\(position.rawValue)"
        case .autohide: return "autohide=\(autohide)"
        case .iconSize: return "size=\(String(format: "%.3f", iconSize))"
        case .magnification: return "magnification=\(magnification)"
        case .magnificationSize: return "magSize=\(String(format: "%.3f", magnificationSize))"
        case .minimizeEffect: return "minimizeEffect=\(minimizeEffect.rawValue)"
        case .animatesLaunch: return "animatesLaunch=\(animatesLaunch)"
        }
    }
}

// MARK: - Hotkey Binding

/// Stores a keyboard shortcut: modifier flags + virtual key code + display name.
public struct HotkeyBinding: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: UInt  // NSEvent.ModifierFlags.rawValue
    public let displayName: String  // from charactersIgnoringModifiers, e.g. "H"

    public init(keyCode: UInt16, modifiers: UInt, displayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
    }
}

// MARK: - Hotkey Matching & Display

public extension HotkeyBinding {

    /// The only modifiers a binding ever stores or matches against.
    ///
    /// CapsLock, Fn and numeric-pad ride along on ordinary key events, so a
    /// binding recorded while one of them was set would never match once it
    /// cleared. Recording and matching must reduce flags through this same
    /// mask — that is why it lives here instead of at each call site.
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// Reduces raw event flags to the modifiers a binding stores.
    static func normalize(_ flags: NSEvent.ModifierFlags) -> UInt {
        flags.intersection(relevantModifiers).rawValue
    }

    /// Whether the flags carry a modifier strong enough to bind to.
    /// Shift alone is rejected — a bare (or shifted) letter would swallow typing.
    static func hasRequiredModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        !flags.intersection([.command, .option, .control]).isEmpty
    }

    /// Whether this binding fires for the given key event values.
    func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        self.keyCode == keyCode && self.modifiers == Self.normalize(modifiers)
    }

    /// Human-readable form in standard macOS modifier order, e.g. `⌃⌥H`.
    var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(displayName)
        return parts.joined()
    }
}

// MARK: - User Preferences

/// Persists user preferences for both modes using UserDefaults.
@MainActor
public final class UserPreferences {

    public static let shared = UserPreferences()

    private let defaults: UserDefaults
    private let prefix = "com.smartdock"

    /// The store this reads and writes.
    ///
    /// Injectable — and deliberately `internal`, so the app can only ever reach
    /// `shared` while tests can hand each case its own scratch domain. Sharing
    /// `UserDefaults.standard` is what made tests trample each other and forced
    /// the whole suite to run sequentially; with a domain per test there is no
    /// shared state left to serialize around.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Backfill

    /// Fills settings a saved profile predates, taking them from the Dock as it is
    /// right now instead of from `DockConfiguration`'s defaults.
    ///
    /// Without this, upgrading restyles the Dock: a profile written before
    /// `minimizeEffect` and `animatesLaunch` existed reads back as genie with
    /// animation on, and the first apply pushes both at a user who had deliberately
    /// chosen Scale with animation off. Only absent keys are written — a profile
    /// that already carries a choice keeps it, otherwise every launch would
    /// overwrite the profile with whatever the Dock happened to hold.
    ///
    /// Separate from `initializeDefaultsIfNeeded`, which only ever runs before the
    /// first profile exists and so can never reach an upgrading install.
    public func backfillMissingSettings(from systemConfig: DockConfiguration) {
        guard isConfigured else { return }

        for key in ["external", "builtin"] {
            guard defaults.object(forKey: "\(prefix).\(key).autohide") != nil else { continue }

            if defaults.object(forKey: "\(prefix).\(key).minimizeEffect") == nil {
                defaults.set(
                    systemConfig.minimizeEffect.rawValue, forKey: "\(prefix).\(key).minimizeEffect")
            }
            if defaults.object(forKey: "\(prefix).\(key).animatesLaunch") == nil {
                defaults.set(
                    systemConfig.animatesLaunch, forKey: "\(prefix).\(key).animatesLaunch")
            }
        }
    }

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
            magnificationSize: systemConfig.magnificationSize,
            minimizeEffect: systemConfig.minimizeEffect,
            animatesLaunch: systemConfig.animatesLaunch
        )
        builtinConfig = DockConfiguration(
            autohide: true,
            position: systemConfig.position,
            iconSize: systemConfig.iconSize,
            magnification: systemConfig.magnification,
            magnificationSize: systemConfig.magnificationSize,
            minimizeEffect: systemConfig.minimizeEffect,
            animatesLaunch: systemConfig.animatesLaunch
        )

        Log.info(
            "First launch — initialized defaults from system config: "
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

    // MARK: - Notifications

    public var notificationsEnabled: Bool {
        get { defaults.bool(forKey: "\(prefix).notificationsEnabled") }
        set { defaults.set(newValue, forKey: "\(prefix).notificationsEnabled") }
    }

    // MARK: - System Sync

    public var syncFromSystemEnabled: Bool {
        get {
            // Default true — sync enabled unless explicitly disabled.
            defaults.object(forKey: "\(prefix).syncFromSystem") == nil
                ? true
                : defaults.bool(forKey: "\(prefix).syncFromSystem")
        }
        set { defaults.set(newValue, forKey: "\(prefix).syncFromSystem") }
    }

    // MARK: - Onboarding

    public var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: "\(prefix).hasSeenOnboarding") }
        set { defaults.set(newValue, forKey: "\(prefix).hasSeenOnboarding") }
    }

    public var hasPromptedAccessibility: Bool {
        get { defaults.bool(forKey: "\(prefix).hasPromptedAccessibility") }
        set { defaults.set(newValue, forKey: "\(prefix).hasPromptedAccessibility") }
    }

    /// Set after Reset Permission flow — tells next launch to open Shortcuts tab,
    /// open System Settings, and watch for Accessibility grant to auto-restart.
    public var pendingAccessibilityGrant: Bool {
        get { defaults.bool(forKey: "\(prefix).pendingAccessibilityGrant") }
        set { defaults.set(newValue, forKey: "\(prefix).pendingAccessibilityGrant") }
    }

    // MARK: - Hotkeys

    public func hotkey(for action: String) -> HotkeyBinding? {
        let keyCodeKey = "\(prefix).hotkey.\(action).keyCode"
        guard defaults.object(forKey: keyCodeKey) != nil else { return nil }
        return HotkeyBinding(
            keyCode: UInt16(defaults.integer(forKey: keyCodeKey)),
            modifiers: UInt(defaults.integer(forKey: "\(prefix).hotkey.\(action).modifiers")),
            displayName: defaults.string(forKey: "\(prefix).hotkey.\(action).displayName") ?? "?"
        )
    }

    public func setHotkey(_ binding: HotkeyBinding?, for action: String) {
        let keyCodeKey = "\(prefix).hotkey.\(action).keyCode"
        let modifiersKey = "\(prefix).hotkey.\(action).modifiers"
        let displayNameKey = "\(prefix).hotkey.\(action).displayName"
        if let binding {
            defaults.set(Int(binding.keyCode), forKey: keyCodeKey)
            defaults.set(Int(binding.modifiers), forKey: modifiersKey)
            defaults.set(binding.displayName, forKey: displayNameKey)
        } else {
            defaults.removeObject(forKey: keyCodeKey)
            defaults.removeObject(forKey: modifiersKey)
            defaults.removeObject(forKey: displayNameKey)
        }
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

        // Old format stored pixels (16–128). New format stores a 0.0–1.0 scale, so
        // anything above 1 is still in the old units and needs converting.
        //
        // Reading as `Double` covers both spellings: UserDefaults keeps numbers as
        // `NSNumber`, which bridges to `Double` whether the value was written as an
        // integer or not. A separate `as? Int` branch used to sit here and could
        // never run.
        for key in [sizeKey, magSizeKey] {
            guard let pixels = defaults.object(forKey: key) as? Double, pixels > 1.0 else {
                continue
            }
            defaults.set(DockConfiguration.pixelsToScale(Int(pixels)), forKey: key)
        }
    }

    // MARK: - Persistence

    private func save(_ config: DockConfiguration, key: String) {
        defaults.set(config.autohide, forKey: "\(prefix).\(key).autohide")
        defaults.set(config.position.rawValue, forKey: "\(prefix).\(key).position")
        defaults.set(config.iconSize, forKey: "\(prefix).\(key).iconSize")
        defaults.set(config.magnification, forKey: "\(prefix).\(key).magnification")
        defaults.set(config.magnificationSize, forKey: "\(prefix).\(key).magnificationSize")
        defaults.set(config.minimizeEffect.rawValue, forKey: "\(prefix).\(key).minimizeEffect")
        defaults.set(config.animatesLaunch, forKey: "\(prefix).\(key).animatesLaunch")
    }

    private func load(key: String) -> DockConfiguration? {
        let autohideKey = "\(prefix).\(key).autohide"
        guard defaults.object(forKey: autohideKey) != nil else { return nil }

        let positionRaw = defaults.string(forKey: "\(prefix).\(key).position") ?? "bottom"
        let iconSize = defaults.double(forKey: "\(prefix).\(key).iconSize")
        let magSize = defaults.double(forKey: "\(prefix).\(key).magnificationSize")
        let effectRaw = defaults.string(forKey: "\(prefix).\(key).minimizeEffect") ?? ""

        // Profiles saved before these two existed have neither key. `bool(forKey:)`
        // would read a missing `animatesLaunch` as false and quietly turn launch
        // animation off for everyone upgrading, so the absent case is spelled out.
        let animationKey = "\(prefix).\(key).animatesLaunch"
        let animates =
            defaults.object(forKey: animationKey) != nil
            ? defaults.bool(forKey: animationKey) : true

        return DockConfiguration(
            autohide: defaults.bool(forKey: autohideKey),
            position: DockPosition(rawValue: positionRaw) ?? .bottom,
            iconSize: iconSize > 0 ? iconSize : 0.2857,
            magnification: defaults.bool(forKey: "\(prefix).\(key).magnification"),
            magnificationSize: magSize > 0 ? magSize : 0.4286,
            minimizeEffect: MinimizeEffect(rawValue: effectRaw) ?? .genie,
            animatesLaunch: animates
        )
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

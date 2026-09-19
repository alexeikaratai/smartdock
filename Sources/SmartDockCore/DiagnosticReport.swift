import Foundation

// MARK: - Diagnostic Report

/// A snapshot of everything worth knowing when someone reports a problem.
///
/// Deliberately holds no personal data: versions, permission flags, display
/// counts and the user's own Dock preferences — nothing about what they type,
/// which apps they run, or which machine this is.
///
/// The value is inert; the app layer gathers the fields and this type decides
/// how they read. Keeping the formatting here makes it testable.
public struct DiagnosticReport: Sendable {

    public struct Hotkey: Sendable {
        public let action: String
        /// `nil` when the action has no shortcut bound.
        public let shortcut: String?

        public init(action: String, shortcut: String?) {
            self.action = action
            self.shortcut = shortcut
        }
    }

    public let appVersion: String
    public let buildNumber: String
    public let systemVersion: String
    public let isAccessibilityGranted: Bool
    public let externalDisplayCount: Int
    public let hasExternalDisplay: Bool
    public let activeProfile: DockProfile
    public let externalConfig: DockConfiguration
    public let builtinConfig: DockConfiguration
    public let notificationsEnabled: Bool
    public let syncFromSystemEnabled: Bool
    public let hotkeys: [Hotkey]

    /// What the last dock apply actually achieved. `nil` before the first one has
    /// been verified. This is the field that distinguishes "the app is misbehaving"
    /// from "macOS refused the change" — the two look identical to a user.
    public let lastApplyOutcome: DockApplyOutcome?

    public init(
        appVersion: String,
        buildNumber: String,
        systemVersion: String,
        isAccessibilityGranted: Bool,
        externalDisplayCount: Int,
        hasExternalDisplay: Bool,
        activeProfile: DockProfile,
        externalConfig: DockConfiguration,
        builtinConfig: DockConfiguration,
        notificationsEnabled: Bool,
        syncFromSystemEnabled: Bool,
        hotkeys: [Hotkey],
        lastApplyOutcome: DockApplyOutcome? = nil
    ) {
        self.lastApplyOutcome = lastApplyOutcome
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.systemVersion = systemVersion
        self.isAccessibilityGranted = isAccessibilityGranted
        self.externalDisplayCount = externalDisplayCount
        self.hasExternalDisplay = hasExternalDisplay
        self.activeProfile = activeProfile
        self.externalConfig = externalConfig
        self.builtinConfig = builtinConfig
        self.notificationsEnabled = notificationsEnabled
        self.syncFromSystemEnabled = syncFromSystemEnabled
        self.hotkeys = hotkeys
    }

    /// Markdown, so it lands readable in a GitHub issue without further editing.
    public var formatted: String {
        var lines: [String] = []

        lines.append("**SmartDock \(appVersion) (build \(buildNumber))**")
        lines.append("- macOS: \(systemVersion)")
        lines.append("- Accessibility: \(isAccessibilityGranted ? "granted" : "NOT granted")")
        lines.append("- External displays: \(externalDisplayCount)")
        // Both facts, because they can disagree: a profile applied on request is
        // exactly the situation a report needs to make visible.
        lines.append("- Active profile: \(activeProfile.displayName)")
        lines.append("- Displays: \(hasExternalDisplay ? "external monitor connected" : "built-in only")")
        if let outcome = lastApplyOutcome {
            // Flagged like a missing permission — a silently refused setting is the
            // same class of problem and just as easy to overlook in a pasted report.
            lines.append("- Last apply: \(outcome.summary)\(outcome.isComplete ? "" : " ⚠️")")
        }
        lines.append("")

        lines.append("**Profiles**")
        lines.append("- External: \(Self.describe(externalConfig))")
        lines.append("- Built-in: \(Self.describe(builtinConfig))")
        lines.append("")

        lines.append("**Settings**")
        lines.append("- Notify on switch: \(notificationsEnabled ? "on" : "off")")
        lines.append("- Auto-import system changes: \(syncFromSystemEnabled ? "on" : "off")")
        lines.append("")

        lines.append("**Shortcuts**")
        if hotkeys.isEmpty {
            lines.append("- none configured")
        } else {
            for hotkey in hotkeys {
                lines.append("- \(hotkey.action): \(hotkey.shortcut ?? "not set")")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Every property a profile carries is listed. A setting the profile applies but
    /// the report omits is the worst case for a bug report: the Dock does something
    /// the reader cannot account for from what they were sent. The switch is
    /// exhaustive so a new `DockProperty` cannot be left out — `showsRecents` was,
    /// for two releases, while the comment above promised otherwise.
    private static func describe(_ config: DockConfiguration) -> String {
        DockProperty.allCases.compactMap { phrase(for: $0, in: config) }.joined(separator: ", ")
    }

    /// `nil` folds a property into its neighbour: the magnification size is only
    /// meaningful while magnification is on, and reads best next to it.
    private static func phrase(for property: DockProperty, in config: DockConfiguration) -> String? {
        switch property {
        case .position: config.position.displayName.lowercased()
        case .autohide: config.autohide ? "auto-hide" : "always visible"
        case .iconSize: "\(DockConfiguration.scaleToPixels(config.iconSize))px"
        case .magnification:
            config.magnification
                ? "magnify \(DockConfiguration.scaleToPixels(config.magnificationSize))px"
                : "no magnification"
        case .magnificationSize: nil
        case .minimizeEffect: config.minimizeEffect.displayName.lowercased()
        case .animatesLaunch: config.animatesLaunch ? "launch animation" : "no launch animation"
        case .showsRecents: config.showsRecents ? "recents" : "no recents"
        case .showsIndicators: config.showsIndicators ? "indicators" : "no indicators"
        case .minimizesToApplication:
            config.minimizesToApplication ? "minimize into app" : "minimize to Dock"
        }
    }
}

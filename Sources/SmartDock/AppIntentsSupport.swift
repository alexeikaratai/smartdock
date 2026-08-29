import AppIntents
import Cocoa
import SmartDockCore

// MARK: - Dispatch

/// Routes an intent into the app's single command path.
///
/// The same reasoning as `ScriptingSupport.dispatch`: Shortcuts is a fourth front
/// door, not a fourth implementation. Everything converges on `performCommand`,
/// which queues the command when an intent launched the app and the managers are
/// not built yet.
@MainActor
private func dispatch(_ command: URLCommand) {
    guard let delegate = NSApp.delegate as? AppDelegate else {
        Log.error("Intent \(command.rawValue) arrived with no app delegate")
        return
    }
    delegate.performCommand(command)
}

// MARK: - Profile Parameter

/// The profile picker Shortcuts shows for `SwitchDockProfileIntent`.
///
/// Kept separate from `DockProfile` rather than conforming that type retroactively:
/// `DockProfile` carries the four-character Apple Event codes, which are frozen
/// public API, and `AppEnum` raw values are a second frozen vocabulary — a saved
/// shortcut stores the raw value. Two independent contracts, two types, with the
/// switches below making them impossible to drift apart silently.
enum ShortcutDockProfile: String, AppEnum {
    case external
    case builtin

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Dock Profile" }

    static var caseDisplayRepresentations: [ShortcutDockProfile: DisplayRepresentation] {
        [
            .external: "External Monitor",
            .builtin: "Built-in Display",
        ]
    }

    var profile: DockProfile {
        switch self {
        case .external: return .external
        case .builtin: return .builtin
        }
    }

    init(_ profile: DockProfile) {
        switch profile {
        case .external: self = .external
        case .builtin: self = .builtin
        }
    }
}

// MARK: - Intents

/// `Refresh Dock` — re-applies whatever the current display setup calls for.
struct RefreshDockIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Dock"
    static let description = IntentDescription(
        "Re-applies the Dock configuration for the displays connected right now.",
        categoryName: "Dock"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        dispatch(.refresh)
        return .result()
    }
}

/// `Switch Dock Profile` — the one action that takes an argument, so a shortcut can
/// force a profile regardless of what is plugged in.
struct SwitchDockProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Dock Profile"
    static let description = IntentDescription(
        "Applies the External Monitor or Built-in Display profile, whatever is currently connected.",
        categoryName: "Dock"
    )

    @Parameter(title: "Profile")
    var profile: ShortcutDockProfile

    static var parameterSummary: some ParameterSummary {
        Summary("Switch Dock to \(\.$profile)")
    }

    init() {}

    /// Lets an App Shortcut pin the profile up front, so Spotlight can offer
    /// "Switch to External Monitor" without asking a follow-up question.
    init(profile: ShortcutDockProfile) {
        self.profile = profile
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        dispatch(profile.profile.command)
        return .result()
    }
}

/// `Toggle Dock Auto-Hide` — flips auto-hide on the profile that is active.
struct ToggleDockAutohideIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Dock Auto-Hide"
    static let description = IntentDescription(
        "Turns auto-hide on or off for the profile that is currently active.",
        categoryName: "Dock"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        dispatch(.toggleAutohide)
        return .result()
    }
}

/// `Open SmartDock Settings` — opens the window, so the app has to come forward.
struct OpenDockSettingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open SmartDock Settings"
    static let description = IntentDescription(
        "Opens the SmartDock settings window.",
        categoryName: "Dock"
    )

    /// The only intent here that shows UI, so the only one that needs the app
    /// brought to the front rather than merely running.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        dispatch(.openSettings)
        return .result()
    }
}

// MARK: - App Shortcuts

/// Puts the intents in Spotlight without the user assembling a shortcut first.
///
/// Every phrase has to contain `\(.applicationName)` — the system rejects a
/// provider at build time otherwise.
struct SmartDockShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshDockIntent(),
            phrases: [
                "Refresh the Dock with \(.applicationName)",
                "Reapply my \(.applicationName) profile",
            ],
            shortTitle: "Refresh Dock",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: SwitchDockProfileIntent(profile: .external),
            phrases: [
                "Switch \(.applicationName) to my external monitor",
                "Use the external Dock profile in \(.applicationName)",
            ],
            shortTitle: "External Profile",
            systemImageName: "display"
        )
        AppShortcut(
            intent: SwitchDockProfileIntent(profile: .builtin),
            phrases: [
                "Switch \(.applicationName) to my built-in display",
                "Use the built-in Dock profile in \(.applicationName)",
            ],
            shortTitle: "Built-in Profile",
            systemImageName: "laptopcomputer"
        )
        AppShortcut(
            intent: ToggleDockAutohideIntent(),
            phrases: [
                "Toggle auto-hide in \(.applicationName)",
                "Hide or show the Dock with \(.applicationName)",
            ],
            shortTitle: "Toggle Auto-Hide",
            systemImageName: "eye.slash"
        )
        AppShortcut(
            intent: OpenDockSettingsIntent(),
            phrases: [
                "Open \(.applicationName) settings"
            ],
            shortTitle: "Open Settings",
            systemImageName: "gearshape"
        )
    }
}

// MARK: - Coverage Tripwire

/// Names the intent that carries each command, so adding a case to `URLCommand`
/// fails the build here until Shortcuts can reach it too.
///
/// The same device as `HotkeyAction(URLCommand)` and the `.sdef` parity test:
/// nothing at runtime depends on this, and that is the point — a command that is
/// scriptable and hotkey-bindable but invisible in Shortcuts is exactly the kind
/// of gap that only surfaces in a bug report.
enum ShortcutCoverage {
    static func intentType(for command: URLCommand) -> any AppIntent.Type {
        switch command {
        case .refresh: return RefreshDockIntent.self
        case .switchToExternal, .switchToBuiltin: return SwitchDockProfileIntent.self
        case .toggleAutohide: return ToggleDockAutohideIntent.self
        case .openSettings: return OpenDockSettingsIntent.self
        }
    }
}

import Cocoa
import SmartDockCore

// MARK: - Dispatch

/// Routes a scripting command into the app's single command path.
///
/// Apple Events are delivered on the main thread by the event manager, which is
/// what makes `assumeIsolated` sound here — `performDefaultImplementation` is
/// inherited as `nonisolated`, so there is no other way to reach `@MainActor`
/// state without hopping off the event's own thread and losing ordering.
private func dispatch(_ command: URLCommand) {
    MainActor.assumeIsolated {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            Log.error("AppleScript command \(command.rawValue) arrived with no app delegate")
            return
        }
        delegate.performCommand(command)
    }
}

// MARK: - Commands

/// `tell application "SmartDock" to refresh`
@objc(SDRefreshCommand)
final class SDRefreshCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        dispatch(.refresh)
        return nil
    }
}

/// `tell application "SmartDock" to switch to external`
@objc(SDSwitchCommand)
final class SDSwitchCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let code = Self.profileCode(from: directParameter) else {
            scriptErrorNumber = NSRequiredArgumentsMissingScriptError
            scriptErrorString = "SmartDock: 'switch to' needs a profile — external or builtin."
            return nil
        }
        guard let profile = DockProfile(appleEventCode: code) else {
            scriptErrorNumber = NSArgumentsWrongScriptError
            scriptErrorString = "SmartDock: unknown dock profile. Use external or builtin."
            return nil
        }
        dispatch(profile.command)
        return nil
    }

    /// Cocoa Scripting hands an enumerator over as an `NSNumber` wrapping its
    /// four-character code, but a script that coerces the value itself can
    /// deliver a raw descriptor instead — both spellings mean the same thing.
    private static func profileCode(from parameter: Any?) -> FourCharCode? {
        if let number = parameter as? NSNumber {
            return number.uint32Value
        }
        if let descriptor = parameter as? NSAppleEventDescriptor {
            return descriptor.enumCodeValue
        }
        return nil
    }
}

/// `tell application "SmartDock" to toggle autohide`
@objc(SDToggleAutohideCommand)
final class SDToggleAutohideCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        dispatch(.toggleAutohide)
        return nil
    }
}

/// `tell application "SmartDock" to show settings`
@objc(SDShowSettingsCommand)
final class SDShowSettingsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        dispatch(.openSettings)
        return nil
    }
}

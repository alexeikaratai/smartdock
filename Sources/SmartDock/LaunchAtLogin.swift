import Foundation
import ServiceManagement
import SmartDockCore

/// Wrapper over SMAppService for managing auto-launch.
/// macOS 13+ — Apple's recommended method instead of LaunchAgents.
enum LaunchAtLogin {

    private static var service: SMAppService {
        SMAppService.mainApp
    }

    static var isEnabled: Bool {
        service.status == .enabled
    }

    static func enable() {
        do {
            try service.register()
            SmartDockCore.Log.info("Launch at Login enabled")
        } catch {
            SmartDockCore.Log.error("Failed to enable Launch at Login: \(error)")
        }
    }

    static func disable() {
        do {
            try service.unregister()
            SmartDockCore.Log.info("Launch at Login disabled")
        } catch {
            SmartDockCore.Log.error("Failed to disable Launch at Login: \(error)")
        }
    }

    static func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }
}

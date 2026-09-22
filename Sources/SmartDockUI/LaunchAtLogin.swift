import Foundation
import ServiceManagement
import SmartDockCore

/// Wrapper over SMAppService for managing auto-launch.
/// macOS 13+ — Apple's recommended method instead of LaunchAgents.
/// The slice of `SMAppService` this app uses. Injectable because registering the
/// test runner as a login item would put `xctest` in the developer's Login Items.
@MainActor
protocol LoginItemRegistering {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemRegistering {
    var isRegistered: Bool { status == .enabled }
}

/// A value rather than a namespace: the login item it talks to is a parameter, so a
/// test never has to swap global state — and could not do so safely while suites run
/// in parallel.
@MainActor
struct LaunchAtLogin {

    // MARK: - Properties

    private let service: any LoginItemRegistering

    init(service: any LoginItemRegistering = SMAppService.mainApp) {
        self.service = service
    }

    var isEnabled: Bool {
        service.isRegistered
    }

    // MARK: - Public

    func enable() {
        do {
            try service.register()
            SmartDockCore.Log.info("Launch at Login enabled")
        } catch {
            SmartDockCore.Log.error("Failed to enable Launch at Login: \(error)")
        }
    }

    func disable() {
        do {
            try service.unregister()
            SmartDockCore.Log.info("Launch at Login disabled")
        } catch {
            SmartDockCore.Log.error("Failed to disable Launch at Login: \(error)")
        }
    }

    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }
}

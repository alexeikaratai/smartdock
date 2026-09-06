import Cocoa
import SmartDockCore

// MARK: - General Tab

/// Contents of the Settings window's General tab: how the **app** behaves, as opposed
/// to what the Dock looks like, which belongs to a profile and lives on the Dock tab.
///
/// The split is not only about window height. "Launch at Login" is not a property of a
/// Dock profile, and reading it directly under a profile picker invited exactly that
/// misreading — more so once the picker starts naming display setups.
///
/// Owns its own state, including the notification-permission observer: the checkbox has
/// to fall back to off when authorisation is refused, and that is this view's business
/// rather than the window's.
@MainActor
final class GeneralTabView: NSView {

    private let service: SmartDockService
    private let prefs: UserPreferences

    private var launchAtLoginCheckbox: NSButton!
    private var notificationsCheckbox: NSButton!
    private var syncFromSystemCheckbox: NSButton!

    // MARK: - Init

    init(service: SmartDockService, prefs: UserPreferences) {
        self.service = service
        self.prefs = prefs
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotificationPermissionChanged),
            name: .smartDockNotificationPermissionChanged,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("GeneralTabView is built programmatically — init(coder:) is unavailable")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Private

    private func buildUI() {
        let margin: CGFloat = 24

        launchAtLoginCheckbox = UI.checkbox(
            "Launch at Login", target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        addSubview(launchAtLoginCheckbox)

        notificationsCheckbox = UI.checkbox(
            "Notify on Profile Switch", target: self, action: #selector(toggleNotifications))
        notificationsCheckbox.state = prefs.notificationsEnabled ? .on : .off
        addSubview(notificationsCheckbox)

        syncFromSystemCheckbox = UI.checkbox(
            "Auto-import System changes", target: self, action: #selector(toggleSyncFromSystem))
        syncFromSystemCheckbox.state = prefs.syncFromSystemEnabled ? .on : .off
        addSubview(syncFromSystemCheckbox)

        let refreshButton = UI.smallButton(
            "Refresh Now", target: self, action: #selector(refreshNow))
        addSubview(refreshButton)

        let quitButton = UI.smallButton(
            "Quit SmartDock", target: self, action: #selector(quitApp))
        addSubview(quitButton)

        NSLayoutConstraint.activate([
            launchAtLoginCheckbox.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),

            notificationsCheckbox.topAnchor.constraint(
                equalTo: launchAtLoginCheckbox.bottomAnchor, constant: 8),
            notificationsCheckbox.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: margin),

            syncFromSystemCheckbox.topAnchor.constraint(
                equalTo: notificationsCheckbox.bottomAnchor, constant: 8),
            syncFromSystemCheckbox.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: margin),

            refreshButton.topAnchor.constraint(
                equalTo: syncFromSystemCheckbox.bottomAnchor, constant: 16),
            refreshButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),

            quitButton.topAnchor.constraint(equalTo: refreshButton.topAnchor),
            quitButton.leadingAnchor.constraint(
                equalTo: refreshButton.trailingAnchor, constant: 8),
            quitButton.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -margin),

            // Defines the view's own height. Shortcuts and About end in
            // `lessThanOrEqualTo` and so measure as zero, which happens to render
            // because AppKit does not clip subviews — but it leaves the tab unable to
            // report how tall it is, which is what the window measurement relies on.
            refreshButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        LaunchAtLogin.toggle()
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func toggleNotifications(_ sender: NSButton) {
        let enabled = sender.state == .on
        prefs.notificationsEnabled = enabled
        if enabled {
            NotificationCenter.default.post(name: .smartDockRequestNotificationAuth, object: nil)
        }
    }

    @objc private func toggleSyncFromSystem(_ sender: NSButton) {
        prefs.syncFromSystemEnabled = sender.state == .on
    }

    @objc private func refreshNow(_ sender: Any) { service.refresh() }

    @objc private func quitApp(_ sender: Any) { NSApp.terminate(nil) }

    /// Authorisation can be refused after the box was ticked, which turns the stored
    /// flag back off — the checkbox has to follow rather than keep claiming it is on.
    @objc private func handleNotificationPermissionChanged(_ notification: Notification) {
        notificationsCheckbox.state = prefs.notificationsEnabled ? .on : .off
    }
}

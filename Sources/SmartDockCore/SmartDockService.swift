import Foundation

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when the service applies a new dock configuration.
    /// `userInfo` contains `SmartDockService.hasExternalKey` (Bool).
    static let smartDockStateDidChange = Notification.Name("com.smartdock.stateDidChange")
}

public extension SmartDockService {
    static let hasExternalKey = "hasExternal"
    /// `userInfo` key for the `DockProfile` in force — what a banner should name.
    static let activeProfileKey = "activeProfile"
}

// MARK: - Delegate

/// Delegate for receiving state change notifications.
@MainActor
public protocol SmartDockServiceDelegate: AnyObject {
    func serviceDidUpdateState(_ service: SmartDockService, hasExternal: Bool)
}

// MARK: - Service

/// Main application service.
/// Links DisplayMonitor and DockController:
/// applies the appropriate DockConfiguration based on whether
/// an external monitor is connected or not.
@MainActor
public final class SmartDockService {

    public weak var delegate: (any SmartDockServiceDelegate)?

    /// Whether the service is active
    public private(set) var isEnabled: Bool = false

    /// Last known state (whether there is an external monitor)
    public private(set) var hasExternalDisplay: Bool = false

    /// Number of active external displays, read live. Used by diagnostics —
    /// `hasExternalDisplay` is the cached state the profile decision was made on.
    public var externalDisplayCount: Int { displayMonitor.externalDisplayCount() }

    /// The profile whose configuration the Dock is holding right now.
    ///
    /// Usually the one the displays select, but `applyProfile(_:)` can put the
    /// other one in force until the next display change, wake or refresh. Anything
    /// that acts on "the active profile" — the auto-hide toggle, the position menu,
    /// an edit imported from System Settings — reads this, not `hasExternalDisplay`:
    /// writing by hardware while the other profile was applied put built-in values
    /// into the external profile.
    public private(set) var activeProfile: DockProfile = .builtin

    /// Names the state in force, for anything that shows it to a person.
    ///
    /// Defined once because it was written twice — the menu bar said "Status: External
    /// monitor connected" and the settings window "Current: External monitor
    /// connected". The same fact, phrased separately, in two files that would have to
    /// be found and edited together the moment a third state exists. Each caller adds
    /// its own prefix; only the wording of the state itself lives here.
    ///
    /// The third state did arrive: a profile applied on request while the displays
    /// would have chosen the other. What is *applied* comes first — that is what the
    /// person is looking at.
    public var activeProfileDescription: String {
        switch (activeProfile, hasExternalDisplay) {
        case (.external, true): "External monitor connected"
        case (.builtin, false): "Built-in display only"
        case (.builtin, true): "Built-in profile · external monitor connected"
        case (.external, false): "External profile · built-in display only"
        }
    }

    /// What the profile in force *asks for*, as stored.
    ///
    /// The counterpart to `currentConfig`, which is what the Dock actually holds after
    /// verification. A control belongs on this side: read the observed state instead
    /// and a refused apply makes the control stop being reversible — the auto-hide
    /// toggle kept re-requesting the same thing and left the stored profile flipped
    /// after two presses. Anything that *displays* state — the menu bar icon, the
    /// tooltip, the refusal notice — stays on `currentConfig`.
    public var activeProfileConfig: DockConfiguration { prefs[activeProfile] }

    /// The dock configuration we last applied (not the transient system state).
    public private(set) var currentConfig: DockConfiguration = DockConfiguration()

    private let displayMonitor: any DisplayMonitoring
    public let dockController: any DockControlling
    private let prefs: UserPreferences

    // MARK: - Init

    public init(
        displayMonitor: any DisplayMonitoring = DisplayMonitor(),
        dockController: any DockControlling = DockController(),
        prefs: UserPreferences = .shared
    ) {
        self.displayMonitor = displayMonitor
        self.dockController = dockController
        self.prefs = prefs

        self.displayMonitor.onConfigurationChanged = { [weak self] in
            self?.handleDisplayChange()
        }

        self.dockController.onExternalConfigChanged = { [weak self] config in
            self?.handleExternalDockChange(config)
        }

        self.dockController.onApplyVerified = { [weak self] outcome, actual in
            self?.handleApplyVerified(outcome, actual: actual)
        }
    }

    // MARK: - Public

    public func start() {
        guard !isEnabled else { return }
        isEnabled = true

        let systemConfig = dockController.readSystemConfig()
        prefs.initializeDefaultsIfNeeded(from: systemConfig)
        // Runs after seeding so a fresh install is a no-op here, and before the
        // first apply so an upgrading one never pushes a default it invented.
        prefs.backfillMissingSettings(from: systemConfig)

        displayMonitor.start()
        dockController.startObservingSystemChanges()
        applyCurrentState()
        Log.info("SmartDock service started")
    }

    public func stop() {
        guard isEnabled else { return }
        isEnabled = false
        displayMonitor.stop()
        dockController.stopObservingSystemChanges()
        Log.info("SmartDock service stopped")
    }

    /// Recalculate and apply state.
    public func refresh() {
        applyCurrentState()
    }

    /// Apply a profile the user asked for by name, overriding the one the current
    /// display setup would select.
    ///
    /// Deliberately **not** implemented as "apply, then `refresh()`": `refresh()`
    /// re-derives the profile from the displays, so it would undo the request
    /// within the same call — and the only time forcing a profile is useful is
    /// precisely when it disagrees with the displays.
    ///
    /// The override holds until the next display change, wake or refresh, at which
    /// point automatic behaviour resumes.
    public func applyProfile(_ profile: DockProfile) {
        guard isEnabled, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        // `hasExternalDisplay` keeps reporting the hardware, which has not changed —
        // only the profile in force has.
        let changed = profile != activeProfile || prefs[profile] != currentConfig
        activeProfile = profile
        apply(prefs[profile])
        Log.info("Applied \(profile.rawValue) profile on request")

        if changed { notifyStateChanged() }
    }

    /// Changes the profile in force and applies it — the one path for every
    /// control that edits "the current profile" in place: the auto-hide toggle,
    /// the position menu, an edit picked up from System Settings.
    public func updateActiveProfile(_ config: DockConfiguration) {
        guard isEnabled, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        let changed = config != currentConfig
        prefs[activeProfile] = config
        apply(config)
        Log.info("Updated \(activeProfile.rawValue) profile in place")

        if changed { notifyStateChanged() }
    }

    // MARK: - Private

    /// Brings the reported state back in line when the Dock did not honour an apply.
    ///
    /// `currentConfig` is recorded optimistically — deliberately so, because the Dock
    /// passes through transient states and reading it back immediately would report
    /// noise. A *refused* setting is not transient, though: left alone, the menu bar
    /// goes on showing a hidden Dock while the Dock sits there in plain view.
    /// Verification runs once that transient window has passed, which makes it the
    /// right moment to reconcile.
    ///
    /// The stored profile is deliberately **not** touched. The user still wants
    /// auto-hide; macOS just would not do it right now. Rewriting the preference
    /// would throw their choice away over a temporary refusal — and it would come
    /// back the next time the profile is applied under conditions that allow it.
    private func handleApplyVerified(_ outcome: DockApplyOutcome, actual: DockConfiguration) {
        guard !outcome.isComplete else { return }

        Log.info("Reporting what the Dock actually holds — \(outcome.summary)")
        currentConfig = actual
        notifyStateChanged()
    }

    private var isApplying = false

    private func handleDisplayChange() {
        guard isEnabled else { return }
        applyCurrentState()
    }

    /// System dock settings changed externally (e.g. via System Settings).
    /// Update the profile in force to match — the Dock already holds the values,
    /// so nothing is applied back.
    private func handleExternalDockChange(_ config: DockConfiguration) {
        guard isEnabled, !isApplying else { return }
        guard prefs.syncFromSystemEnabled else { return }

        prefs[activeProfile] = config
        Log.info("External dock change detected — updated \(activeProfile.rawValue) profile")

        currentConfig = config
        notifyStateChanged()
    }

    /// `isEnabled` is checked here rather than only in the callers, because this is
    /// what `refresh()` reaches — and `refresh()` is what "Refresh Now" and the
    /// auto-hide toggle in the menu bar call. Without it a service the user had
    /// switched **off** still moved the Dock on demand, which is not what the power
    /// icon promises. `start()` sets `isEnabled` before its own call, so the first
    /// apply is unaffected.
    private func applyCurrentState() {
        guard isEnabled, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        let previousConfig = currentConfig
        let previousExternal = hasExternalDisplay

        let external = displayMonitor.hasExternalDisplay()
        hasExternalDisplay = external
        activeProfile = DockProfile(hasExternalDisplay: external)

        let config = prefs[activeProfile]
        Log.displayChange(
            external
                ? "External display detected — applying external config"
                : "No external displays — applying built-in config")
        apply(config)

        // Only notify observers when state actually changed.
        if config != previousConfig || external != previousExternal {
            notifyStateChanged()
        }
    }

    /// Records the configuration as ours and hands it to the Dock.
    private func apply(_ config: DockConfiguration) {
        currentConfig = config
        dockController.apply(config)
    }

    private func notifyStateChanged() {
        delegate?.serviceDidUpdateState(self, hasExternal: hasExternalDisplay)
        NotificationCenter.default.post(
            name: .smartDockStateDidChange,
            object: self,
            userInfo: [
                SmartDockService.hasExternalKey: hasExternalDisplay,
                SmartDockService.activeProfileKey: activeProfile,
            ]
        )
    }
}

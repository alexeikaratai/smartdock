import Foundation

// MARK: - Protocol

/// Managing Dock preferences: autohide, position, icon size, magnification.
@MainActor
public protocol DockControlling: AnyObject {
    /// Called when system dock settings change externally (e.g. via System Settings).
    var onExternalConfigChanged: ((DockConfiguration) -> Void)? { get set }

    /// Current autohide state
    func isAutoHideEnabled() -> Bool

    /// Set the autohide state. Returns true on success.
    @discardableResult
    func setAutoHide(_ enabled: Bool) -> Bool

    /// Apply a full dock configuration. Diff-based — only changes properties that differ from system state.
    /// Uses AppleScript → System Events for immediate dock update.
    @discardableResult
    func apply(_ config: DockConfiguration) -> Bool

    /// Read the current system dock configuration.
    func readSystemConfig() -> DockConfiguration

    /// Start observing system dock preference changes via KVO.
    func startObservingSystemChanges()

    /// Stop observing system dock preference changes.
    func stopObservingSystemChanges()
}

// MARK: - Implementation

/// Manages Dock preferences via AppleScript → System Events.
///
/// Each property is set in its own `tell` block so that a failure in one
/// (e.g. magnification size when magnification is off) does not prevent
/// the others from being applied. This avoids the need for `killall Dock`
/// entirely — System Events tells the Dock to update itself gracefully.
public final class DockController: DockControlling {

    public var onExternalConfigChanged: ((DockConfiguration) -> Void)?

    /// Last config we applied via AppleScript — used to distinguish our own
    /// changes from external ones in KVO callbacks.
    private var lastAppliedConfig: DockConfiguration?

    private var prefsObserver: DockPrefsObserver?
    private var pendingExternalCheck: DispatchWorkItem?

    public init() {}

    // MARK: - DockControlling

    public func isAutoHideEnabled() -> Bool {
        readSystemConfig().autohide
    }

    @discardableResult
    public func setAutoHide(_ enabled: Bool) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set autohide to \(enabled)
                end tell
            end tell
            """
        )
    }

    /// Read current dock settings directly from the system.
    /// Creates a fresh UserDefaults instance to avoid stale cached values
    /// after AppleScript changes dock preferences via System Events.
    /// Sizes are returned as 0.0–1.0 scale (converted from pixel tilesize).
    public func readSystemConfig() -> DockConfiguration {
        guard let d = UserDefaults(suiteName: "com.apple.dock") else {
            return DockConfiguration()
        }
        let orientationRaw = d.string(forKey: "orientation") ?? "bottom"
        let tilesize = d.integer(forKey: "tilesize")
        let largesize = d.integer(forKey: "largesize")

        return DockConfiguration(
            autohide: d.bool(forKey: "autohide"),
            position: DockPosition(rawValue: orientationRaw) ?? .bottom,
            iconSize: tilesize > 0 ? DockConfiguration.pixelsToScale(tilesize) : 0.2857,
            magnification: d.bool(forKey: "magnification"),
            magnificationSize: largesize > 0 ? DockConfiguration.pixelsToScale(largesize) : 0.4286
        )
    }

    @discardableResult
    public func apply(_ config: DockConfiguration) -> Bool {
        // Read current system state and only apply properties that differ.
        // Each AppleScript poke can cause the Dock to briefly flash — skipping
        // unchanged properties avoids spurious dock appearances.
        let current = readSystemConfig()

        var allOk = true
        var changed: [String] = []

        if config.position != current.position {
            changed.append("position=\(config.position.rawValue)")
            if !applyPosition(config.position) { allOk = false }
        }

        if config.autohide != current.autohide {
            changed.append("autohide=\(config.autohide)")
            if !applyAutohide(config.autohide) { allOk = false }
        }

        // Tolerance covers 1-pixel rounding difference (~0.009 scale).
        if abs(config.iconSize - current.iconSize) > 0.01 {
            changed.append("size=\(String(format: "%.3f", config.iconSize))")
            if !applyIconSize(config.iconSize) { allOk = false }
        }

        if config.magnification != current.magnification {
            changed.append("magnification=\(config.magnification)")
            if !applyMagnification(config.magnification) { allOk = false }
        }

        if config.magnification && abs(config.magnificationSize - current.magnificationSize) > 0.01 {
            changed.append("magSize=\(String(format: "%.3f", config.magnificationSize))")
            if !applyMagnificationSize(config.magnificationSize) { allOk = false }
        }

        if changed.isEmpty {
            Log.info("Dock config unchanged — skipped AppleScript")
        } else {
            let status = allOk ? "" : " [some failed]"
            Log.info("Dock config applied: \(changed.joined(separator: " "))\(status)")
        }

        // Snapshot what we applied — KVO will fire for our own changes,
        // and we compare against this to filter them out.
        lastAppliedConfig = config

        return allOk
    }

    // MARK: - System Change Observation

    public func startObservingSystemChanges() {
        stopObservingSystemChanges()

        lastAppliedConfig = readSystemConfig()

        let observer = DockPrefsObserver()
        observer.onChange = { [weak self] in
            self?.handleExternalChange()
        }
        observer.start()
        prefsObserver = observer
        Log.info("Dock system preferences observer started")
    }

    public func stopObservingSystemChanges() {
        pendingExternalCheck?.cancel()
        pendingExternalCheck = nil
        prefsObserver?.stop()
        prefsObserver = nil
    }

    /// Debounced handler for KVO callbacks. System Settings may change
    /// multiple keys at once — wait 0.5s after the last change before reading.
    private func handleExternalChange() {
        pendingExternalCheck?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingExternalCheck = nil

            let systemConfig = self.readSystemConfig()

            // If the system config matches what we last applied (within tolerance),
            // this is our own change echoing back — ignore it.
            if let lastApplied = self.lastAppliedConfig,
               systemConfig.approximatelyEquals(lastApplied) {
                return
            }

            self.lastAppliedConfig = systemConfig
            Log.info("External dock preferences change detected")
            self.onExternalConfigChanged?(systemConfig)
        }
        pendingExternalCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - Per-Property AppleScript

    private func applyPosition(_ position: DockPosition) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set screen edge to \(position.appleScriptValue)
                end tell
            end tell
            """)
    }

    private func applyAutohide(_ autohide: Bool) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set autohide to \(autohide)
                end tell
            end tell
            """)
    }

    private func applyIconSize(_ scale: Double) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set dock size to \(scale)
                end tell
            end tell
            """)
    }

    private func applyMagnification(_ enabled: Bool) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set magnification to \(enabled)
                end tell
            end tell
            """)
    }

    private func applyMagnificationSize(_ scale: Double) -> Bool {
        runAppleScript("""
            tell application "System Events"
                tell dock preferences
                    set magnification size to \(scale)
                end tell
            end tell
            """)
    }

    // MARK: - Private

    @discardableResult
    private func runAppleScript(_ source: String) -> Bool {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error = error {
            Log.error("AppleScript error: \(error[NSAppleScript.errorMessage] ?? "unknown") — script: \(source)")
            return false
        }
        return true
    }
}

// MARK: - Dock Preferences KVO Observer

/// Observes `com.apple.dock` UserDefaults keys via KVO.
/// When any process (System Settings, `defaults write`) changes dock preferences,
/// `cfprefsd` delivers KVO callbacks. This is a small NSObject helper so that
/// DockController itself doesn't need to inherit from NSObject.
@MainActor
private final class DockPrefsObserver: NSObject {

    var onChange: (() -> Void)?

    /// Accessed from deinit (nonisolated) — must be nonisolated(unsafe).
    private nonisolated(unsafe) var observedDefaults: UserDefaults?
    private let watchedKeys = [
        "autohide", "orientation", "tilesize",
        "magnification", "largesize",
    ]

    /// Thread-safe flag — accessed from deinit (nonisolated) and @MainActor methods.
    private nonisolated(unsafe) var isObserving = false

    func start() {
        guard let defaults = UserDefaults(suiteName: "com.apple.dock") else { return }
        observedDefaults = defaults
        for key in watchedKeys {
            defaults.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }
        isObserving = true
    }

    func stop() {
        guard isObserving, let defaults = observedDefaults else { return }
        isObserving = false
        for key in watchedKeys {
            defaults.removeObserver(self, forKeyPath: key)
        }
        observedDefaults = nil
    }

    override nonisolated func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        DispatchQueue.main.async { @MainActor [weak self] in
            self?.onChange?()
        }
    }

    deinit {
        // Safety: remove observers if stop() wasn't called.
        guard isObserving, let defaults = observedDefaults else { return }
        for key in watchedKeys {
            defaults.removeObserver(self, forKeyPath: key)
        }
    }
}

// MARK: - Position Helpers

fileprivate extension DockPosition {
    /// Value for AppleScript `screen edge` property
    var appleScriptValue: String {
        switch self {
        case .bottom: return "bottom"
        case .left:   return "left"
        case .right:  return "right"
        }
    }
}

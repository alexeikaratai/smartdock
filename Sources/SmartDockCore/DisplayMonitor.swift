import Cocoa
import CoreGraphics
import Foundation

// MARK: - Protocol

/// Monitor display configuration.
/// Protocol allows for implementation substitution in tests.
@MainActor
public protocol DisplayMonitoring: AnyObject {
    /// Called when the number of external displays actually changes.
    var onConfigurationChanged: (() -> Void)? { get set }

    /// Number of active external monitors
    func externalDisplayCount() -> Int

    /// Whether there is at least one external monitor
    func hasExternalDisplay() -> Bool

    /// Start monitoring
    func start()

    /// Stop monitoring
    func stop()
}

// MARK: - Implementation

/// Observes monitor connection/disconnection through CoreGraphics API.
/// Uses `CGDisplayRegisterReconfigurationCallback` — an event-driven approach,
/// without polling or timers.
///
/// Only fires `onConfigurationChanged` when the external display count
/// actually changes. This filters out CG callbacks triggered by Dock
/// restarts or other non-display reconfiguration events.
@MainActor
public final class DisplayMonitor: DisplayMonitoring {

    public var onConfigurationChanged: (() -> Void)?

    /// Thread-safe flag — accessed from deinit (nonisolated) and main actor methods.
    private nonisolated(unsafe) var isRunning = false

    /// Track the last known external display count to filter spurious callbacks.
    private var lastExternalCount: Int = -1

    /// Debounce: CG fires callbacks during space transitions (Mission Control,
    /// fullscreen enter/exit). The display count can fluctuate transiently.
    /// We wait for callbacks to stop arriving before checking the count.
    private var pendingCheck: DispatchWorkItem?
    private let settleDelay: TimeInterval

    /// Separate work item for wake rechecks — must not be cancelled by CG callbacks.
    private var pendingWakeCheck: DispatchWorkItem?

    /// Longer than `settleDelay`: CG keeps reporting stale counts for a moment
    /// after wake, so this waits out the settle window and then some.
    private let wakeDelay: TimeInterval

    /// How the external display count is obtained.
    ///
    /// Injectable for the same reason `DockController`'s script runner is: the real
    /// implementation asks CoreGraphics about the hardware attached right now, so
    /// the debounce and change-detection logic around it could otherwise only be
    /// exercised by physically plugging a monitor in.
    private let countExternalDisplays: () -> Int

    public init(
        settleDelay: TimeInterval = 1.0,
        wakeDelay: TimeInterval = 2.0,
        countExternalDisplays: (() -> Int)? = nil
    ) {
        self.settleDelay = settleDelay
        self.wakeDelay = wakeDelay
        self.countExternalDisplays = countExternalDisplays ?? DisplayMonitor.activeExternalDisplayCount
    }

    deinit {
        guard isRunning else { return }
        isRunning = false

        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        // Can't call @MainActor removeWakeObservers() from nonisolated deinit,
        // so remove observer directly. NSNotificationCenter.removeObserver is thread-safe.
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Public

    public func externalDisplayCount() -> Int {
        countExternalDisplays()
    }

    /// Asks CoreGraphics which external displays are actually usable right now.
    private static func activeExternalDisplayCount() -> Int {
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        let error = CGGetActiveDisplayList(maxDisplays, &displayIDs, &displayCount)
        guard error == .success else { return 0 }

        var externalCount = 0
        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            // Skip built-in displays
            guard CGDisplayIsBuiltin(id) == 0 else { continue }
            // Skip sleeping/inactive externals — clamshell mode, monitor in standby,
            // phantom connections from USB-C hubs etc.
            guard CGDisplayIsActive(id) != 0, CGDisplayIsAsleep(id) == 0 else { continue }
            externalCount += 1
        }
        return externalCount
    }

    public func hasExternalDisplay() -> Bool {
        externalDisplayCount() > 0
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        // Snapshot the current state so the first real change is detected
        lastExternalCount = externalDisplayCount()

        let result = CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )

        if result != .success {
            isRunning = false
            return
        }

        addWakeObservers()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        pendingCheck?.cancel()
        pendingWakeCheck?.cancel()

        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        removeWakeObservers()
    }

    // MARK: - Internal (called from C callback on main queue)

    /// Called by the C callback after display reconfiguration completes.
    /// Debounces: cancels any pending check and reschedules, so the check
    /// always runs 1s after the *last* CG callback. This lets hardware
    /// settle before we read the display count.
    /// Internal rather than private so tests can drive the debounce directly —
    /// the only other caller is a C function pointer.
    func handleReconfiguration() {
        // A callback already dispatched to the main queue can arrive after `stop()`
        // removed the registration. `handleWake` has always guarded against this;
        // without the same check here a stopped monitor could still fire.
        guard isRunning else { return }

        pendingCheck?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCheck = nil
            let current = self.externalDisplayCount()
            if current != self.lastExternalCount {
                Log.displayChange("External display count changed: \(self.lastExternalCount) → \(current)")
                self.lastExternalCount = current
                self.onConfigurationChanged?()
            }
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    // MARK: - Wake Observers

    /// Subscribe to wake events that can leave the dock in a wrong state.
    private func addWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(handleWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleWake(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        Log.info("Wake observers registered")
    }

    private func removeWakeObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// On wake, force re-check display state after a settle delay.
    /// CG may report incorrect display count immediately after wake,
    /// so we wait for the system to stabilize.
    /// Internal so tests can drive it directly. Posting a real
    /// `NSWorkspace.didWakeNotification` would wake every other monitor alive in
    /// the process — including those belonging to suites running in parallel.
    @objc func handleWake(_ notification: Notification) {
        guard isRunning else { return }
        Log.info("System wake detected (\(notification.name.rawValue)) — scheduling display re-check")
        forceRecheck()
    }

    /// Re-check display state after wake. Only fires callback if the
    /// display count actually changed — otherwise the dock is already
    /// in the correct state and any AppleScript poke would disrupt fullscreen.
    ///
    /// Uses a separate `pendingWakeCheck` so CG callbacks can't cancel it.
    /// Internal for the same reason as `handleReconfiguration`.
    func forceRecheck() {
        pendingWakeCheck?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let current = self.externalDisplayCount()
            Log.displayChange("Wake re-check: external displays = \(current) (was \(self.lastExternalCount))")
            if current != self.lastExternalCount {
                self.lastExternalCount = current
                self.onConfigurationChanged?()
            }
        }
        pendingWakeCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wakeDelay, execute: work)
    }
}

// MARK: - Callback Filtering

/// Whether a CoreGraphics reconfiguration callback describes a real change in
/// which displays are attached.
///
/// CG fires this callback for far more than connect/disconnect: Mission Control and
/// fullscreen transitions report `desktopShapeChanged`, resolution changes report
/// `setMode`, and rearranging displays reports `moved`. Re-applying dock config during
/// those transitions interferes with macOS's own dock show/hide behavior, so only
/// add/remove/enable/disable counts.
///
/// CG also calls twice per change — once with `beginConfiguration` and once on
/// completion. We react only to completion, when the new configuration is in place.
func shouldReactToDisplayChange(_ flags: CGDisplayChangeSummaryFlags) -> Bool {
    guard !flags.contains(.beginConfigurationFlag) else { return false }

    let topologyFlags: CGDisplayChangeSummaryFlags = [
        .addFlag,
        .removeFlag,
        .enabledFlag,
        .disabledFlag,
    ]
    return !flags.isDisjoint(with: topologyFlags)
}

// MARK: - C Callback

/// Internal rather than private so a test can invoke it the way CoreGraphics
/// would. Everything it does — filtering the flags, recovering the monitor from an
/// opaque pointer, hopping to the main queue — is logic that only ever runs when a
/// display is physically plugged in otherwise.
func displayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard shouldReactToDisplayChange(flags) else { return }
    guard let userInfo = userInfo else { return }
    let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    DispatchQueue.main.async { @MainActor in
        monitor.handleReconfiguration()
    }
}

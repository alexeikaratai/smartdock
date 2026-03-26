import Foundation
import CoreGraphics
import Cocoa

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
    private let settleDelay: TimeInterval = 1.0

    /// Separate work item for wake rechecks — must not be cancelled by CG callbacks.
    private var pendingWakeCheck: DispatchWorkItem?

    public init() {}

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
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        let error = CGGetActiveDisplayList(maxDisplays, &displayIDs, &displayCount)
        guard error == .success else { return 0 }

        var externalCount = 0
        for i in 0..<Int(displayCount) {
            if CGDisplayIsBuiltin(displayIDs[i]) == 0 {
                externalCount += 1
            }
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

        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        removeWakeObservers()
    }

    // MARK: - Internal (called from C callback on main queue)

    /// Called by the C callback after display reconfiguration completes.
    /// Debounces: waits for callbacks to stop arriving, then checks if the
    /// external display count actually changed. This prevents reacting to
    /// transient fluctuations during Mission Control / fullscreen transitions.
    fileprivate func handleReconfiguration() {
        pendingCheck?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
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
    /// No space change observer — applying dock config via AppleScript itself
    /// triggers space change notifications, causing infinite feedback loops.
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
    @objc private func handleWake(_ notification: Notification) {
        guard isRunning else { return }
        Log.info("System wake detected (\(notification.name.rawValue)) — scheduling display re-check")
        forceRecheck()
    }

    /// Force a display state re-check. Unlike handleReconfiguration(), this
    /// always fires the callback regardless of whether the count changed,
    /// because after sleep the dock may be in an incorrect state even if
    /// the display count is the same.
    ///
    /// Uses a separate `pendingWakeCheck` so CG callbacks can't cancel it.
    private func forceRecheck() {
        pendingWakeCheck?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let current = self.externalDisplayCount()
            Log.displayChange("Wake re-check: external displays = \(current) (was \(self.lastExternalCount))")
            self.lastExternalCount = current
            self.onConfigurationChanged?()
        }
        pendingWakeCheck = work
        // Longer delay after wake — system needs more time to stabilize displays
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}

// MARK: - C Callback

/// CoreGraphics calls the callback twice: with the beginConfigurationChange flag
/// and then without it (completion). We react only to completion,
/// when the new configuration is already applied.
///
/// We also filter by flags: only react to actual display add/remove/enable/disable
/// events. This avoids reacting to space transitions (Mission Control, fullscreen
/// enter/exit) which fire `kCGDisplayDesktopShapeChangedFlag` or
/// `kCGDisplaySetModeFlag` — re-applying dock config during these transitions
/// can interfere with macOS's normal dock show/hide behavior.
private func displayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    // Ignore the start of reconfiguration — react only to completion.
    guard !flags.contains(CGDisplayChangeSummaryFlags(rawValue: 1)) else { return }

    // Only react to actual display topology changes (add/remove/enable/disable).
    // Ignore mode changes, moves, and desktop shape changes — these fire during
    // Mission Control and fullscreen transitions and would cause spurious
    // dock config re-application.
    let addRemoveFlags = CGDisplayChangeSummaryFlags(rawValue:
        0x10 |   // kCGDisplayAddFlag
        0x20 |   // kCGDisplayRemoveFlag
        0x100 |  // kCGDisplayEnabledFlag
        0x200    // kCGDisplayDisabledFlag
    )
    guard !flags.isDisjoint(with: addRemoveFlags) else { return }

    guard let userInfo = userInfo else { return }
    let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // Callback comes on an arbitrary thread — switch to main
    DispatchQueue.main.async { @MainActor in
        monitor.handleReconfiguration()
    }
}

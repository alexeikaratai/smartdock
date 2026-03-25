import Foundation
import CoreGraphics

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

    public init() {}

    deinit {
        guard isRunning else { return }
        isRunning = false

        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
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
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    // MARK: - Internal (called from C callback on main queue)

    /// Called by the C callback after display reconfiguration completes.
    /// Only fires `onConfigurationChanged` if the external display count changed.
    fileprivate func handleReconfiguration() {
        let current = externalDisplayCount()
        if current != lastExternalCount {
            Log.displayChange("External display count changed: \(lastExternalCount) → \(current)")
            lastExternalCount = current
            onConfigurationChanged?()
        }
    }
}

// MARK: - C Callback

/// CoreGraphics calls the callback twice: with the beginConfigurationChange flag
/// and then without it (completion). We react only to completion,
/// when the new configuration is already applied.
private func displayReconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    // Ignore the start of reconfiguration — react only to completion.
    guard !flags.contains(CGDisplayChangeSummaryFlags(rawValue: 1)) else { return }

    guard let userInfo = userInfo else { return }
    let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // Callback comes on an arbitrary thread — switch to main
    DispatchQueue.main.async { @MainActor in
        monitor.handleReconfiguration()
    }
}

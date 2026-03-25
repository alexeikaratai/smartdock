import Foundation
import CoreGraphics

// MARK: - Protocol

/// Monitor display configuration.
/// Protocol allows for implementation substitution in tests.
@MainActor
public protocol DisplayMonitoring: AnyObject {
    /// Called when display reconfiguration is completed
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
@MainActor
public final class DisplayMonitor: DisplayMonitoring {

    public var onConfigurationChanged: (() -> Void)?

    private var isRunning = false

    public init() {}

    deinit {
        // deinit is nonisolated — inline the cleanup directly
        // instead of calling @MainActor stop()
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
    // Bit 0 (rawValue 1) = begin configuration change.
    guard !flags.contains(CGDisplayChangeSummaryFlags(rawValue: 1)) else { return }

    guard let userInfo = userInfo else { return }
    let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // Callback comes on an arbitrary thread — switch to main
    DispatchQueue.main.async { @MainActor in
        monitor.onConfigurationChanged?()
    }
}

import Foundation

// MARK: - Dock Apply Outcome

/// What an `apply` actually achieved, established by reading the Dock back
/// afterwards instead of trusting AppleScript's return value.
///
/// `NSAppleScript` reports success as soon as the script *ran*. It says nothing
/// about whether System Events honoured the request — a property can be accepted,
/// ignored, or silently dropped, and all three look identical from the caller's
/// side. That gap makes "the app says it applied but nothing happened" the single
/// hardest thing to diagnose from a bug report, so the app establishes the answer
/// itself rather than assuming.
public struct DockApplyOutcome: Sendable, Equatable {

    /// Properties this apply set out to change.
    public let requested: [DockProperty]

    /// Properties that were pushed but the Dock did not take.
    public let rejected: [DockProperty]

    public init(requested: [DockProperty], rejected: [DockProperty]) {
        self.requested = requested
        self.rejected = rejected
    }

    /// Whether everything asked for actually landed.
    public var isComplete: Bool {
        rejected.isEmpty
    }

    /// Nothing needed changing — the Dock already matched, so no script ran.
    public static let noWorkNeeded = DockApplyOutcome(requested: [], rejected: [])

    /// Compares the config that was applied against what the Dock holds now.
    ///
    /// Only properties in `requested` can be reported as rejected: anything else
    /// that differs was changed by something outside the app between the push and
    /// this read, and blaming the apply for it would be wrong.
    public static func verifying(
        _ config: DockConfiguration,
        against actual: DockConfiguration,
        requested: [DockProperty]
    ) -> DockApplyOutcome {
        let stillDifferent = Set(config.differences(from: actual))
        return DockApplyOutcome(
            requested: requested,
            rejected: requested.filter { stillDifferent.contains($0) })
    }

    /// What to tell the user when macOS refused part of the last apply, or `nil`
    /// when there is nothing to report.
    ///
    /// Separate from `summary`, which names the requested properties too — useful
    /// in a log, noise in a menu. Here only the refusal matters: the person asked
    /// for auto-hide and did not get it, and until this existed the only trace was
    /// the diagnostic report, so the usual case — macOS declining auto-hide while an
    /// app is fullscreen — looked exactly like the app doing nothing at all.
    public var refusalNotice: String? {
        guard !isComplete else { return nil }
        return "macOS declined \(rejected.map(\.displayName).joined(separator: ", "))"
    }

    /// One-line summary for logs and the diagnostic report.
    public var summary: String {
        guard !requested.isEmpty else { return "nothing to apply" }
        guard !isComplete else {
            return "applied \(requested.map(\.rawValue).joined(separator: ", "))"
        }
        return "Dock ignored \(rejected.map(\.rawValue).joined(separator: ", "))"
            + " (requested \(requested.map(\.rawValue).joined(separator: ", ")))"
    }
}

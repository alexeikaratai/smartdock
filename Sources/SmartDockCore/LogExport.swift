import Foundation

// MARK: - Log Export

/// Builds the `log show` invocation behind **Export Logs**, and cleans up what it
/// returns before anyone attaches it to an issue.
///
/// Pure, so the two details that are easy to get wrong — and were, by hand, more
/// than once — are pinned by tests rather than rediscovered: the tool must be
/// reached by absolute path, and info-level messages need an explicit flag.
public enum LogExport {

    /// The app's own subsystem. The export is scoped to it and never to the whole
    /// system log, which would sweep up every other app on the machine.
    public static let subsystem = "com.smartdock.app"

    /// Absolute path on purpose: `zsh` has a **builtin** named `log`, so a bare
    /// `log show` silently runs the shell's own command instead of this tool.
    public static let toolPath = "/usr/bin/log"

    /// Arguments for `log show`.
    ///
    /// `--info` is a safety net. `Log` deliberately records at notice level or
    /// above, which `log show` returns by default — but anything that ever slips
    /// down to info would otherwise vanish from the export without a trace, and an
    /// export with silent gaps is worse than one that is merely verbose.
    public static func arguments(lastHours: Int) -> [String] {
        [
            "show",
            "--predicate", "subsystem == \"\(subsystem)\"",
            "--info",
            "--style", "compact",
            "--last", "\(max(1, lastHours))h",
        ]
    }

    /// Suggested filename, sortable and unambiguous: `SmartDock-log-2026-08-17-2317.txt`.
    public static func defaultFileName(at date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "SmartDock-log-%04d-%02d-%02d-%02d%02d.txt",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Replaces the user's home directory with `~`.
    ///
    /// SmartDock logs bundle and executable paths, and on a normal install those
    /// carry the account name. The diagnostic report is deliberately free of
    /// anything identifying; an exported log attached to the same issue should not
    /// undo that.
    public static func redacting(_ text: String, homeDirectory: String) -> String {
        guard !homeDirectory.isEmpty, homeDirectory != "/" else { return text }

        // Trailing slash trimmed so "/Users/name" and "/Users/name/" behave alike.
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        return text.replacingOccurrences(of: home, with: "~")
    }
}

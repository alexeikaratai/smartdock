import OSLog

/// Centralized logging through Logger API (macOS 14+).
/// Logs are visible in Console.app → filter by subsystem «com.smartdock.app».
///
/// Everything here logs at **notice** or above, never `.info` or `.debug`.
/// That is a deliberate choice, not a stylistic one: macOS keeps info- and
/// debug-level messages in a memory buffer and does not write them to the
/// persistent store, so they are gone by the time anyone runs `log show` or
/// **Export Logs**. A diagnostic trail nobody can retrieve afterwards is not a
/// diagnostic trail. The volume here is a handful of lines per display change,
/// so persisting it costs nothing worth measuring.
public enum Log {

    private static let subsystem = "com.smartdock.app"

    private static let general = Logger(subsystem: subsystem, category: "general")
    private static let display = Logger(subsystem: subsystem, category: "display")

    // MARK: - General

    public static func info(_ message: String) {
        general.notice("\(message, privacy: .public)")
    }

    public static func error(_ message: String) {
        general.error("\(message, privacy: .public)")
    }

    // MARK: - Display

    public static func displayChange(_ message: String) {
        display.notice("\(message, privacy: .public)")
    }
}

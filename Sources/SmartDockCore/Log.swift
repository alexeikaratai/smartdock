import OSLog

/// Centralized logging through Logger API (macOS 14+).
/// Logs are visible in Console.app → filter by subsystem «com.smartdock.app».
public enum Log {

    private static let subsystem = "com.smartdock.app"

    private static let general = Logger(subsystem: subsystem, category: "general")
    private static let display = Logger(subsystem: subsystem, category: "display")
    private static let dock    = Logger(subsystem: subsystem, category: "dock")

    // MARK: - General

    public static func info(_ message: String) {
        general.info("\(message, privacy: .public)")
    }

    public static func error(_ message: String) {
        general.error("\(message, privacy: .public)")
    }

    // MARK: - Display

    public static func displayChange(_ message: String) {
        display.info("\(message, privacy: .public)")
    }

    // MARK: - Dock

    public static func dockAction(_ message: String) {
        dock.info("\(message, privacy: .public)")
    }
}

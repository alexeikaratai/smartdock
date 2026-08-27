import Foundation
import Testing

@testable import SmartDockCore

@Suite("Log export")
struct LogExportTests {

    // MARK: - Invocation

    /// `zsh` has a builtin named `log`. Invoking the tool by bare name runs that
    /// instead and returns nothing useful — which is exactly how a log capture in
    /// this project was once read as "the app produced no logs at all".
    @Test func toolIsReachedByAbsolutePath() {
        #expect(LogExport.toolPath.hasPrefix("/"), "A bare name would hit the shell builtin")
        #expect(LogExport.toolPath == "/usr/bin/log")
    }

    /// A safety net for anything logged below notice. `Log` records at notice or
    /// above precisely so the trail survives to be exported, but a stray `.info`
    /// call would otherwise be dropped from the file without any sign it existed.
    @Test func infoLevelIsRequested() {
        #expect(LogExport.arguments(lastHours: 24).contains("--info"))
    }

    /// Scoped to this app. Exporting the whole system log would sweep in every
    /// other app running on the machine.
    @Test func exportIsScopedToOurSubsystemOnly() throws {
        let args = LogExport.arguments(lastHours: 24)

        let predicate = try #require(args.first { $0.contains("subsystem") })

        #expect(predicate == "subsystem == \"com.smartdock.app\"")
    }

    @Test func timeWindowIsPassedThrough() {
        #expect(LogExport.arguments(lastHours: 6).contains("6h"))
        #expect(LogExport.arguments(lastHours: 48).contains("48h"))
    }

    /// A zero or negative window would make `log show` reject the argument.
    @Test(arguments: [0, -5]) func windowIsClampedToAtLeastAnHour(hours: Int) {
        #expect(LogExport.arguments(lastHours: hours).contains("1h"))
    }

    /// The arguments go to Process, not through a shell, so the predicate must
    /// arrive as one element — splitting it would make `log` reject the command.
    @Test func predicateIsASingleArgument() throws {
        let args = LogExport.arguments(lastHours: 24)

        let index = try #require(args.firstIndex(of: "--predicate"))

        #expect(args[index + 1].contains("com.smartdock.app"))
    }

    // MARK: - Filename

    @Test func fileNameIsSortableAndTimestamped() throws {
        let name = LogExport.defaultFileName(
            at: try Self.date(2026, 8, 17, 23, 17),
            calendar: Calendar(identifier: .gregorian))

        #expect(name == "SmartDock-log-2026-08-17-2317.txt")
    }

    @Test func fileNamePadsSingleDigits() throws {
        let name = LogExport.defaultFileName(
            at: try Self.date(2026, 1, 5, 9, 3),
            calendar: Calendar(identifier: .gregorian))

        #expect(name == "SmartDock-log-2026-01-05-0903.txt")
    }

    // MARK: - Privacy

    /// The app logs bundle and executable paths, which contain the account name on
    /// any normal install. The diagnostic report is scrubbed of anything
    /// identifying; a log attached to the same issue must not undo that.
    @Test func homeDirectoryIsRedacted() {
        let line = "AppUpdateWatcher started on /Users/somebody/Applications/SmartDock.app/Contents/MacOS/SmartDock"

        let redacted = LogExport.redacting(line, homeDirectory: "/Users/somebody")

        #expect(!redacted.contains("somebody"))
        #expect(redacted.contains("~/Applications/SmartDock.app"))
    }

    @Test func everyOccurrenceIsRedactedNotJustTheFirst() {
        let text = """
            copied /Users/somebody/a to /Users/somebody/b
            watching /Users/somebody/c
            """

        let redacted = LogExport.redacting(text, homeDirectory: "/Users/somebody")

        #expect(!redacted.contains("somebody"))
        #expect(redacted.components(separatedBy: "~").count - 1 == 3)
    }

    @Test func trailingSlashOnHomeIsHandled() {
        let line = "path /Users/somebody/Library"

        #expect(
            LogExport.redacting(line, homeDirectory: "/Users/somebody/")
                == LogExport.redacting(line, homeDirectory: "/Users/somebody"))
    }

    /// A degenerate home would otherwise replace every `/` in the file.
    @Test(arguments: ["/", ""]) func degenerateHomeDirectoryIsIgnored(home: String) {
        let line = "path /Users/somebody/Library"

        #expect(LogExport.redacting(line, homeDirectory: home) == line)
    }

    @Test func textWithoutHomePathsIsUnchanged() {
        let line = "Dock apply verified: applied autohide"

        #expect(LogExport.redacting(line, homeDirectory: "/Users/somebody") == line)
    }

    // MARK: - Helpers

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute

        return try #require(Calendar(identifier: .gregorian).date(from: components))
    }
}

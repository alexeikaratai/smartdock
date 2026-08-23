import XCTest

@testable import SmartDockCore

final class LogExportTests: XCTestCase {

    // MARK: - Invocation

    /// `zsh` has a builtin named `log`. Invoking the tool by bare name runs that
    /// instead and returns nothing useful — which is exactly how a log capture in
    /// this project was once read as "the app produced no logs at all".
    func testToolIsReachedByAbsolutePath() {
        XCTAssertTrue(LogExport.toolPath.hasPrefix("/"), "A bare name would hit the shell builtin")
        XCTAssertEqual(LogExport.toolPath, "/usr/bin/log")
    }

    /// A safety net for anything logged below notice. `Log` records at notice or
    /// above precisely so the trail survives to be exported, but a stray `.info`
    /// call would otherwise be dropped from the file without any sign it existed.
    func testInfoLevelIsRequested() {
        XCTAssertTrue(LogExport.arguments(lastHours: 24).contains("--info"))
    }

    /// Scoped to this app. Exporting the whole system log would sweep in every
    /// other app running on the machine.
    func testExportIsScopedToOurSubsystemOnly() {
        let args = LogExport.arguments(lastHours: 24)
        let predicate = try? XCTUnwrap(args.first { $0.contains("subsystem") })

        XCTAssertEqual(predicate, "subsystem == \"com.smartdock.app\"")
    }

    func testTimeWindowIsPassedThrough() {
        XCTAssertTrue(LogExport.arguments(lastHours: 6).contains("6h"))
        XCTAssertTrue(LogExport.arguments(lastHours: 48).contains("48h"))
    }

    /// A zero or negative window would make `log show` reject the argument.
    func testWindowIsClampedToAtLeastAnHour() {
        XCTAssertTrue(LogExport.arguments(lastHours: 0).contains("1h"))
        XCTAssertTrue(LogExport.arguments(lastHours: -5).contains("1h"))
    }

    /// The arguments go to Process, not through a shell, so the predicate must
    /// arrive as one element — splitting it would make `log` reject the command.
    func testPredicateIsASingleArgument() {
        let args = LogExport.arguments(lastHours: 24)
        let index = try? XCTUnwrap(args.firstIndex(of: "--predicate"))

        XCTAssertNotNil(index)
        if let index { XCTAssertTrue(args[index + 1].contains("com.smartdock.app")) }
    }

    // MARK: - Filename

    func testFileNameIsSortableAndTimestamped() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        components.hour = 23
        components.minute = 17

        let date = try? XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
        let name = LogExport.defaultFileName(at: date ?? Date(), calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(name, "SmartDock-log-2026-08-17-2317.txt")
    }

    func testFileNamePadsSingleDigits() {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        components.hour = 9
        components.minute = 3

        let date = try? XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
        let name = LogExport.defaultFileName(at: date ?? Date(), calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(name, "SmartDock-log-2026-01-05-0903.txt")
    }

    // MARK: - Privacy

    /// The app logs bundle and executable paths, which contain the account name on
    /// any normal install. The diagnostic report is scrubbed of anything
    /// identifying; a log attached to the same issue must not undo that.
    func testHomeDirectoryIsRedacted() {
        let line = "AppUpdateWatcher started on /Users/somebody/Applications/SmartDock.app/Contents/MacOS/SmartDock"

        let redacted = LogExport.redacting(line, homeDirectory: "/Users/somebody")

        XCTAssertFalse(redacted.contains("somebody"))
        XCTAssertTrue(redacted.contains("~/Applications/SmartDock.app"))
    }

    func testEveryOccurrenceIsRedactedNotJustTheFirst() {
        let text = """
            copied /Users/somebody/a to /Users/somebody/b
            watching /Users/somebody/c
            """

        let redacted = LogExport.redacting(text, homeDirectory: "/Users/somebody")

        XCTAssertFalse(redacted.contains("somebody"))
        XCTAssertEqual(redacted.components(separatedBy: "~").count - 1, 3)
    }

    func testTrailingSlashOnHomeIsHandled() {
        let line = "path /Users/somebody/Library"

        XCTAssertEqual(
            LogExport.redacting(line, homeDirectory: "/Users/somebody/"),
            LogExport.redacting(line, homeDirectory: "/Users/somebody"))
    }

    /// A degenerate home would otherwise replace every `/` in the file.
    func testDegenerateHomeDirectoryIsIgnored() {
        let line = "path /Users/somebody/Library"

        XCTAssertEqual(LogExport.redacting(line, homeDirectory: "/"), line)
        XCTAssertEqual(LogExport.redacting(line, homeDirectory: ""), line)
    }

    func testTextWithoutHomePathsIsUnchanged() {
        let line = "Dock apply verified: applied autohide"
        XCTAssertEqual(LogExport.redacting(line, homeDirectory: "/Users/somebody"), line)
    }
}

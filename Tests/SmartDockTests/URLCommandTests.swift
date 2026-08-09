import XCTest

@testable import SmartDockCore

final class URLCommandTests: XCTestCase {

    // MARK: - Helpers

    private func parse(_ string: String) -> URLCommand? {
        guard let url = URL(string: string) else {
            XCTFail("Not a valid URL: \(string)")
            return nil
        }
        return URLCommand(url: url)
    }

    // MARK: - Canonical URLs

    /// Every command must parse back from the URL it advertises — this is the
    /// contract the README and any external integration relies on.
    func testEveryCommandParsesFromItsOwnURL() {
        for command in URLCommand.allCases {
            XCTAssertEqual(
                parse(command.url), command,
                "\(command.rawValue) failed to round-trip through \(command.url)")
        }
    }

    func testCanonicalURLs() {
        XCTAssertEqual(parse("smartdock://refresh"), .refresh)
        XCTAssertEqual(parse("smartdock://switch/external"), .switchToExternal)
        XCTAssertEqual(parse("smartdock://switch/builtin"), .switchToBuiltin)
        XCTAssertEqual(parse("smartdock://toggle-autohide"), .toggleAutohide)
        XCTAssertEqual(parse("smartdock://settings"), .openSettings)
    }

    // MARK: - Accepted Variations

    func testSchemeIsCaseInsensitive() {
        XCTAssertEqual(parse("SmartDock://refresh"), .refresh)
        XCTAssertEqual(parse("SMARTDOCK://refresh"), .refresh)
    }

    func testCommandIsCaseInsensitive() {
        XCTAssertEqual(parse("smartdock://REFRESH"), .refresh)
        XCTAssertEqual(parse("smartdock://Switch/External"), .switchToExternal)
    }

    func testHyphenatedBuiltInIsAccepted() {
        XCTAssertEqual(
            parse("smartdock://switch/built-in"), .switchToBuiltin,
            "The UI labels the mode \"Built-in\", so accept that spelling")
    }

    func testSlashSeparatedToggleAutohideIsAccepted() {
        XCTAssertEqual(parse("smartdock://toggle/autohide"), .toggleAutohide)
    }

    func testPreferencesIsAnAliasForSettings() {
        XCTAssertEqual(parse("smartdock://preferences"), .openSettings)
    }

    func testTrailingSlashIsIgnored() {
        XCTAssertEqual(parse("smartdock://refresh/"), .refresh)
        XCTAssertEqual(parse("smartdock://switch/external/"), .switchToExternal)
    }

    // MARK: - Rejected Input

    func testForeignSchemeIsRejected() {
        XCTAssertNil(parse("https://example.com/refresh"))
        XCTAssertNil(parse("otherapp://refresh"))
    }

    func testUnknownCommandIsRejected() {
        XCTAssertNil(parse("smartdock://explode"))
        XCTAssertNil(parse("smartdock://switch/sideways"))
    }

    func testIncompleteSwitchIsRejected() {
        XCTAssertNil(
            parse("smartdock://switch"),
            "\"switch\" without a target is ambiguous and must not silently pick one")
    }

    func testEmptyCommandIsRejected() {
        XCTAssertNil(parse("smartdock://"))
    }

    func testExtraPathSegmentsAreRejected() {
        XCTAssertNil(parse("smartdock://switch/external/now"))
    }
}

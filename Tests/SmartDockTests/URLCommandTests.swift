import Foundation
import Testing

@testable import SmartDockCore

@Suite("URL parsing")
struct URLCommandTests {

    // MARK: - Helpers

    private func parse(_ string: String) throws -> URLCommand? {
        let url = try #require(URL(string: string), "Not a valid URL: \(string)")
        return URLCommand(url: url)
    }

    // MARK: - Canonical URLs

    /// Every command must parse back from the URL it advertises — this is the
    /// contract the README and any external integration relies on.
    @Test(arguments: URLCommand.allCases)
    func everyCommandParsesFromItsOwnURL(command: URLCommand) throws {
        #expect(
            try parse(command.url) == command,
            "\(command.rawValue) failed to round-trip through \(command.url)")
    }

    @Test func canonicalURLs() throws {
        #expect(try parse("smartdock://refresh") == .refresh)
        #expect(try parse("smartdock://switch/external") == .switchToExternal)
        #expect(try parse("smartdock://switch/builtin") == .switchToBuiltin)
        #expect(try parse("smartdock://toggle-autohide") == .toggleAutohide)
        #expect(try parse("smartdock://settings") == .openSettings)
    }

    // MARK: - Accepted Variations

    @Test(arguments: ["SmartDock://refresh", "SMARTDOCK://refresh"])
    func schemeIsCaseInsensitive(url: String) throws {
        #expect(try parse(url) == .refresh)
    }

    @Test func commandIsCaseInsensitive() throws {
        #expect(try parse("smartdock://REFRESH") == .refresh)
        #expect(try parse("smartdock://Switch/External") == .switchToExternal)
    }

    @Test func hyphenatedBuiltInIsAccepted() throws {
        #expect(
            try parse("smartdock://switch/built-in") == .switchToBuiltin,
            "The UI labels the mode \"Built-in\", so accept that spelling")
    }

    @Test func slashSeparatedToggleAutohideIsAccepted() throws {
        #expect(try parse("smartdock://toggle/autohide") == .toggleAutohide)
    }

    @Test func preferencesIsAnAliasForSettings() throws {
        #expect(try parse("smartdock://preferences") == .openSettings)
    }

    @Test func trailingSlashIsIgnored() throws {
        #expect(try parse("smartdock://refresh/") == .refresh)
        #expect(try parse("smartdock://switch/external/") == .switchToExternal)
    }

    // MARK: - Rejected Input

    @Test(arguments: ["https://example.com/refresh", "otherapp://refresh"])
    func foreignSchemeIsRejected(url: String) throws {
        #expect(try parse(url) == nil)
    }

    @Test(arguments: ["smartdock://explode", "smartdock://switch/sideways"])
    func unknownCommandIsRejected(url: String) throws {
        #expect(try parse(url) == nil)
    }

    @Test func incompleteSwitchIsRejected() throws {
        #expect(
            try parse("smartdock://switch") == nil,
            "\"switch\" without a target is ambiguous and must not silently pick one")
    }

    @Test func emptyCommandIsRejected() throws {
        #expect(try parse("smartdock://") == nil)
    }

    @Test func extraPathSegmentsAreRejected() throws {
        #expect(try parse("smartdock://switch/external/now") == nil)
    }
}

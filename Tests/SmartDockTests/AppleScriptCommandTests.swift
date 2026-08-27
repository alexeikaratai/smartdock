import Foundation
import Testing

@testable import SmartDockCore

@Suite("AppleScript vocabulary")
struct AppleScriptCommandTests {

    // MARK: - Four-Character Codes

    /// These are the app's public scripting API. A script identifies an enumerator
    /// by code, never by name, so changing one silently breaks every script already
    /// written against it — pinned to literals rather than recomputed.
    @Test func enumeratorCodesAreStable() {
        #expect(DockProfile.external.appleEventCode == 0x4465_7874, "'Dext'")
        #expect(DockProfile.builtin.appleEventCode == 0x4462_6C74, "'Dblt'")
    }

    @Test func everyProfileHasADistinctCode() {
        let codes = Set(DockProfile.allCases.map(\.appleEventCode))

        #expect(
            codes.count == DockProfile.allCases.count,
            "Two profiles sharing a code would make one unreachable from AppleScript")
    }

    // MARK: - Decoding

    @Test(arguments: DockProfile.allCases)
    func codeRoundTripsToItsProfile(profile: DockProfile) {
        #expect(DockProfile(appleEventCode: profile.appleEventCode) == profile)
    }

    /// An unknown enumerator must be rejected so the command reports a script
    /// error, rather than quietly applying whichever profile happened to be first.
    @Test(arguments: [FourCharCode(0x0000_0000), 0x4462_6C75])  // 'Dblu' — one byte off
    func unknownCodeIsRejected(code: FourCharCode) {
        #expect(DockProfile(appleEventCode: code) == nil)
    }

    // MARK: - Command Mapping

    @Test func profilesMapToTheMatchingURLCommand() {
        #expect(DockProfile.external.command == .switchToExternal)
        #expect(DockProfile.builtin.command == .switchToBuiltin)
    }

    /// AppleScript, `smartdock://` and hotkeys must stay one vocabulary. If a
    /// profile ever mapped to a command that isn't a profile switch, scripting
    /// would silently do something else.
    @Test(arguments: DockProfile.allCases)
    func everyProfileMapsToASwitchCommand(profile: DockProfile) {
        #expect(
            [URLCommand.switchToExternal, .switchToBuiltin].contains(profile.command),
            "\(profile) maps to \(profile.command), which is not a profile switch")
    }

    // MARK: - Dictionary Parity

    /// The `.sdef` and the Swift enum are two hand-written copies of the same
    /// codes, in different languages, that nothing else forces to agree. This
    /// reads the shipped dictionary and checks them against each other.
    @Test(arguments: DockProfile.allCases)
    func codesMatchTheShippedScriptingDictionary(profile: DockProfile) throws {
        let sdef = try #require(Self.scriptingDictionary(), "SmartDock.sdef not found")
        let code = Self.fourCharString(profile.appleEventCode)

        #expect(
            sdef.contains("name=\"\(profile.rawValue)\" code=\"\(code)\""),
            """
            SmartDock.sdef has no enumerator <name="\(profile.rawValue)" code="\(code)">. \
            The dictionary and DockProfile.appleEventCode have drifted apart.
            """)
    }

    /// Each command in the dictionary points at a class that must exist in the app
    /// target. A typo here fails at runtime with "unrecognised command", not at build.
    @Test func dictionaryDeclaresACommandClassForEveryCommand() throws {
        let sdef = try #require(Self.scriptingDictionary(), "SmartDock.sdef not found")

        let commandCount = sdef.components(separatedBy: "<command ").count - 1
        let cocoaClassCount = sdef.components(separatedBy: "<cocoa class=").count - 1

        #expect(commandCount > 0, "Dictionary declares no commands")
        #expect(
            commandCount == cocoaClassCount,
            "Every <command> needs a <cocoa class=...> or AppleScript cannot dispatch it")
    }

    // MARK: - Helpers

    /// Locates the dictionary relative to this source file — it is a bundle
    /// resource of the app target, which the test target does not link.
    private static func scriptingDictionary() -> String? {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SmartDockTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let sdef = repoRoot.appendingPathComponent("Resources/SmartDock.sdef")
        return try? String(contentsOf: sdef, encoding: .utf8)
    }

    /// Unpacks an OSType back into its four characters, for readable failures.
    private static func fourCharString(_ code: FourCharCode) -> String {
        String(bytes: (0..<4).reversed().map { UInt8((code >> ($0 * 8)) & 0xFF) }, encoding: .ascii) ?? ""
    }
}

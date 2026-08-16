import XCTest

@testable import SmartDockCore

/// Scratch preferences domain. File-scope rather than a static member so the
/// `nonisolated` setUp/tearDown overrides can reach it without hopping actors.
private let scratchSuiteName = "com.smartdock.tests.dock"

/// Covers `DockController.readSystemConfig` — the translation from the Dock's own
/// preference keys into a `DockConfiguration`.
///
/// Runs against a scratch domain, never `com.apple.dock`: a test that wrote there
/// would reconfigure the developer's actual Dock mid-suite.
@MainActor
final class DockSystemConfigTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Self.clearScratchDomain()
    }

    override func tearDown() {
        Self.clearScratchDomain()
        super.tearDown()
    }

    // MARK: - Helpers

    /// `nonisolated` because setUp/tearDown are inherited that way — XCTestCase
    /// declares them outside the main actor, so an override cannot add isolation.
    private nonisolated static func clearScratchDomain() {
        UserDefaults.standard.removePersistentDomain(forName: scratchSuiteName)

        // cfprefsd leaves an empty plist behind for any domain that was opened.
        // Remove it so a test run leaves nothing in ~/Library/Preferences.
        let path = ("~/Library/Preferences/\(scratchSuiteName).plist" as NSString).expandingTildeInPath
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeSubject() throws -> (defaults: UserDefaults, controller: DockController) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: scratchSuiteName))
        return (defaults, DockController(suiteName: scratchSuiteName))
    }

    // MARK: - Booleans

    func testAutohideIsRead() throws {
        let (defaults, controller) = try makeSubject()

        defaults.set(true, forKey: "autohide")
        XCTAssertTrue(controller.readSystemConfig().autohide)

        defaults.set(false, forKey: "autohide")
        XCTAssertFalse(controller.readSystemConfig().autohide)
    }

    func testMagnificationIsRead() throws {
        let (defaults, controller) = try makeSubject()

        defaults.set(true, forKey: "magnification")
        XCTAssertTrue(controller.readSystemConfig().magnification)
    }

    /// The Dock omits keys that sit at their default, so absence must read as
    /// false rather than as "unknown".
    func testMissingBooleansReadAsFalse() throws {
        let (_, controller) = try makeSubject()

        let config = controller.readSystemConfig()
        XCTAssertFalse(config.autohide)
        XCTAssertFalse(config.magnification)
    }

    // MARK: - Position

    func testEveryOrientationIsRecognised() throws {
        let (defaults, controller) = try makeSubject()

        for position in DockPosition.allCases {
            defaults.set(position.rawValue, forKey: "orientation")
            XCTAssertEqual(controller.readSystemConfig().position, position)
        }
    }

    /// A value macOS might introduce later must not crash or pick something odd.
    func testUnknownOrientationFallsBackToBottom() throws {
        let (defaults, controller) = try makeSubject()

        defaults.set("diagonal", forKey: "orientation")
        XCTAssertEqual(controller.readSystemConfig().position, .bottom)
    }

    func testMissingOrientationFallsBackToBottom() throws {
        let (_, controller) = try makeSubject()
        XCTAssertEqual(controller.readSystemConfig().position, .bottom)
    }

    // MARK: - Sizes

    func testIconSizeIsConvertedFromPixels() throws {
        let (defaults, controller) = try makeSubject()

        defaults.set(48, forKey: "tilesize")
        XCTAssertEqual(
            controller.readSystemConfig().iconSize,
            DockConfiguration.pixelsToScale(48),
            accuracy: 0.0001)
    }

    func testMagnifiedSizeIsConvertedFromPixels() throws {
        let (defaults, controller) = try makeSubject()

        defaults.set(96, forKey: "largesize")
        XCTAssertEqual(
            controller.readSystemConfig().magnificationSize,
            DockConfiguration.pixelsToScale(96),
            accuracy: 0.0001)
    }

    /// `integer(forKey:)` returns 0 for a missing key, which would convert to the
    /// smallest possible icon. The fallbacks exist so an unset Dock reads as normal.
    func testMissingSizesFallBackToTheMacOSDefaults() throws {
        let (_, controller) = try makeSubject()

        let config = controller.readSystemConfig()
        XCTAssertEqual(config.iconSize, 0.2857, accuracy: 0.0001)
        XCTAssertEqual(config.magnificationSize, 0.4286, accuracy: 0.0001)
    }

    func testZeroSizesFallBackRatherThanCollapsingToMinimum() throws {
        let (defaults, controller) = try makeSubject()

        defaults.set(0, forKey: "tilesize")
        defaults.set(0, forKey: "largesize")

        let config = controller.readSystemConfig()
        XCTAssertEqual(config.iconSize, 0.2857, accuracy: 0.0001)
        XCTAssertEqual(config.magnificationSize, 0.4286, accuracy: 0.0001)
    }

    // MARK: - Round Trip

    /// What the Dock reports must read back as the same settings — otherwise
    /// `apply` would see a difference on every pass and keep poking it.
    func testAFullyPopulatedDomainReadsBackIntact() throws {
        let (defaults, controller) = try makeSubject()

        defaults.set(true, forKey: "autohide")
        defaults.set("right", forKey: "orientation")
        defaults.set(64, forKey: "tilesize")
        defaults.set(true, forKey: "magnification")
        defaults.set(112, forKey: "largesize")

        let config = controller.readSystemConfig()

        XCTAssertTrue(config.autohide)
        XCTAssertEqual(config.position, .right)
        XCTAssertTrue(config.magnification)
        XCTAssertEqual(config.iconSize, DockConfiguration.pixelsToScale(64), accuracy: 0.0001)
        XCTAssertEqual(config.magnificationSize, DockConfiguration.pixelsToScale(112), accuracy: 0.0001)

        XCTAssertTrue(
            config.differences(from: config).isEmpty,
            "A config read from the system must need no work to apply back to it")
    }
}

import Foundation
import Testing

@testable import SmartDockCore

/// Covers `DockController.readSystemConfig` — the translation from the Dock's own
/// preference keys into a `DockConfiguration`.
///
/// Every test gets its own scratch domain, never `com.apple.dock`: a test that
/// wrote there would reconfigure the developer's actual Dock mid-suite.
@Suite("Reading system config")
@MainActor
struct DockSystemConfigTests {

    /// A controller pointed at a throwaway domain, plus the domain itself.
    private func makeSubject() -> (store: InMemoryDefaults, controller: DockController) {
        let store = InMemoryDefaults()
        return (store, DockController(openDefaults: { store }))
    }

    // MARK: - Booleans

    @Test func autohideIsRead() {
        let (store, controller) = makeSubject()

        store.set(true, forKey: "autohide")
        #expect(controller.readSystemConfig().autohide)

        store.set(false, forKey: "autohide")
        #expect(!controller.readSystemConfig().autohide)
    }

    @Test func magnificationIsRead() {
        let (store, controller) = makeSubject()

        store.set(true, forKey: "magnification")

        #expect(controller.readSystemConfig().magnification)
    }

    /// The Dock omits keys that sit at their default, so absence must read as
    /// false rather than as "unknown".
    @Test func missingBooleansReadAsFalse() {
        let (_, controller) = makeSubject()

        let config = controller.readSystemConfig()

        #expect(!config.autohide)
        #expect(!config.magnification)
    }

    // MARK: - Position

    @Test(arguments: DockPosition.allCases)
    func everyOrientationIsRecognised(position: DockPosition) {
        let (store, controller) = makeSubject()

        store.set(position.rawValue, forKey: "orientation")

        #expect(controller.readSystemConfig().position == position)
    }

    /// A value macOS might introduce later must not crash or pick something odd.
    @Test func unknownOrientationFallsBackToBottom() {
        let (store, controller) = makeSubject()

        store.set("diagonal", forKey: "orientation")

        #expect(controller.readSystemConfig().position == .bottom)
    }

    @Test func missingOrientationFallsBackToBottom() {
        let (_, controller) = makeSubject()

        #expect(controller.readSystemConfig().position == .bottom)
    }

    // MARK: - Sizes

    @Test func iconSizeIsConvertedFromPixels() {
        let (store, controller) = makeSubject()

        store.set(48, forKey: "tilesize")

        expectClose(controller.readSystemConfig().iconSize, DockConfiguration.pixelsToScale(48))
    }

    @Test func magnifiedSizeIsConvertedFromPixels() {
        let (store, controller) = makeSubject()

        store.set(96, forKey: "largesize")

        expectClose(
            controller.readSystemConfig().magnificationSize, DockConfiguration.pixelsToScale(96))
    }

    /// `integer(forKey:)` returns 0 for a missing key, which would convert to the
    /// smallest possible icon. The fallbacks exist so an unset Dock reads as normal.
    @Test func missingSizesFallBackToTheMacOSDefaults() {
        let (_, controller) = makeSubject()

        let config = controller.readSystemConfig()

        expectClose(config.iconSize, 0.2857)
        expectClose(config.magnificationSize, 0.4286)
    }

    @Test func zeroSizesFallBackRatherThanCollapsingToMinimum() {
        let (store, controller) = makeSubject()

        store.set(0, forKey: "tilesize")
        store.set(0, forKey: "largesize")

        let config = controller.readSystemConfig()

        expectClose(config.iconSize, 0.2857)
        expectClose(config.magnificationSize, 0.4286)
    }

    /// `UserDefaults(suiteName:)` returns nil for a domain that cannot be opened.
    /// Reading on regardless would crash; the app falls back to the macOS defaults
    /// so the Dock is left alone rather than reconfigured from garbage.
    @Test func anUnopenableStoreReadsAsTheDefaults() {
        let controller = DockController(openDefaults: { nil })

        let config = controller.readSystemConfig()

        #expect(config == DockConfiguration())
    }

    // MARK: - Round Trip

    /// What the Dock reports must read back as the same settings — otherwise
    /// `apply` would see a difference on every pass and keep poking it.
    @Test func aFullyPopulatedDomainReadsBackIntact() {
        let (store, controller) = makeSubject()

        store.set(true, forKey: "autohide")
        store.set("right", forKey: "orientation")
        store.set(64, forKey: "tilesize")
        store.set(true, forKey: "magnification")
        store.set(112, forKey: "largesize")

        let config = controller.readSystemConfig()

        #expect(config.autohide)
        #expect(config.position == .right)
        #expect(config.magnification)
        expectClose(config.iconSize, DockConfiguration.pixelsToScale(64))
        expectClose(config.magnificationSize, DockConfiguration.pixelsToScale(112))

        #expect(
            config.differences(from: config).isEmpty,
            "A config read from the system must need no work to apply back to it")
    }
}

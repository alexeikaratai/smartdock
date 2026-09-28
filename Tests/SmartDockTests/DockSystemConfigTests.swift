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
        let subject = makeSubjectWithGlobal()
        // The global store is held by the controller's own closure, so dropping the
        // reference here still leaves it readable.
        return (subject.store, subject.controller)
    }

    /// Both domains, for the tests that care which one a key lives in.
    private func makeSubjectWithGlobal() -> (
        store: InMemoryDefaults, global: InMemoryDefaults, controller: DockController
    ) {
        let store = InMemoryDefaults()
        let global = InMemoryDefaults()
        let controller = DockController(
            openDomain: { $0 == DockController.globalPreferencesDomain ? global : store })
        return (store, global, controller)
    }

    // MARK: - Every Property

    /// Every property has to come back out of the domain that holds it.
    ///
    /// `readSystemConfig` builds its result through an initialiser where every argument
    /// has a default, so a property it forgets to read still compiles and quietly
    /// returns *our* default. Nothing else notices: the profile is then diffed against a
    /// value the system never reported, and the first apply pushes a setting nobody
    /// touched. The switch is exhaustive, so a new property does not compile here until
    /// it names its key — and which domain, since the menu bar is in `NSGlobalDomain`
    /// while everything else is in the Dock's.
    @Test(arguments: DockProperty.allCases)
    func everyPropertyIsReadFromItsSystemKey(property: DockProperty) {
        let (store, global, controller) = makeSubjectWithGlobal()
        // The magnified size is deliberately not diffed while magnification is off,
        // exactly as its slider is disabled in System Settings.
        store.set(true, forKey: "magnification")

        // Each value differs from what this property reads as when its key is absent.
        let edit: (domain: InMemoryDefaults, key: String, value: Any) =
            switch property {
            case .position: (store, "orientation", "left")
            case .autohide: (store, "autohide", true)
            case .iconSize: (store, "tilesize", 80)
            case .magnification: (store, "magnification", true)
            case .magnificationSize: (store, "largesize", 100)
            case .minimizeEffect: (store, "mineffect", "scale")
            case .animatesLaunch: (store, "launchanim", false)
            case .showsRecents: (store, "show-recents", false)
            case .showsIndicators: (store, "show-process-indicators", false)
            case .minimizesToApplication: (store, "minimize-to-application", true)
            case .autohideMenuBar: (global, "_HIHideMenuBar", true)
            }
        edit.domain.set(edit.value, forKey: edit.key)

        let differences = controller.readSystemConfig().differences(from: DockConfiguration())

        #expect(differences.contains(property), "`\(edit.key)` is not read")
    }

    // MARK: - The Other Domain

    /// The menu bar is the one setting System Events files under `dock preferences`
    /// that macOS does **not** keep in `com.apple.dock`. Reading it from the Dock's
    /// domain would report "menu bar visible" for everyone who hides it, and the first
    /// apply would then show a menu bar they had deliberately hidden.
    @Test func theMenuBarIsReadFromTheGlobalDomainOnly() {
        let (store, global, controller) = makeSubjectWithGlobal()

        // Planted in the wrong domain: must change nothing.
        store.set(true, forKey: "_HIHideMenuBar")
        #expect(!controller.readSystemConfig().autohideMenuBar, "read from the Dock's domain")

        global.set(true, forKey: "_HIHideMenuBar")
        #expect(controller.readSystemConfig().autohideMenuBar)
    }

    /// Measured with the key deleted: System Events reports `false`. An absent key has
    /// to read the same way, or every apply would push a script for a setting nobody
    /// changed.
    @Test func anAbsentMenuBarKeyReadsAsVisible() {
        let (_, _, controller) = makeSubjectWithGlobal()

        #expect(!controller.readSystemConfig().autohideMenuBar)
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

    @Test func unknownMinimizeEffectFallsBackToGenie() {
        let (store, controller) = makeSubject()

        store.set("suck", forKey: "mineffect")

        #expect(controller.readSystemConfig().minimizeEffect == .genie)
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
        let controller = DockController(openDomain: { _ in nil })

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

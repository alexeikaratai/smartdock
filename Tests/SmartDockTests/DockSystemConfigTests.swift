import Foundation
import Testing

@testable import SmartDockCore

/// Covers `DockController.readSystemConfig` — the translation from the Dock's own
/// preference keys into a `DockConfiguration`.
///
/// Every test gets its own scratch domain, never `com.apple.dock`: a test that
/// wrote there would reconfigure the developer's actual Dock mid-suite.
/// Collects the scripts a controller would have run.
private final class ScriptLog {
    private(set) var scripts: [String] = []
    func record(_ script: String) { scripts.append(script) }
}

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
        let (store, global, _, controller) = makeSubjectWithBothMenuBarDomains()
        return (store, global, controller)
    }

    /// All three stores. The menu bar spans two of them: the popup's value and the half
    /// that does the hiding.
    private func makeSubjectWithBothMenuBarDomains() -> (
        store: InMemoryDefaults, global: InMemoryDefaults, centre: InMemoryDefaults,
        controller: DockController
    ) {
        let (store, global, centre, controller, _) = makeSubjectRecordingScripts()
        return (store, global, centre, controller)
    }

    /// All three stores plus the scripts the controller would have run.
    ///
    /// `runScript` is injected even where a test only reads: left at its default it is
    /// the real System Events, so an `apply` here would reconfigure the machine running
    /// the suite — which is exactly what it did until this fixture stopped it.
    private func makeSubjectRecordingScripts() -> (
        store: InMemoryDefaults, global: InMemoryDefaults, centre: InMemoryDefaults,
        controller: DockController, scripts: () -> [String]
    ) {
        let store = InMemoryDefaults()
        let global = InMemoryDefaults()
        let centre = InMemoryDefaults()
        let log = ScriptLog()
        let controller = DockController(
            openDomain: {
                switch $0 {
                case DockController.globalPreferencesDomain: global
                case DockController.controlCentreDomain: centre
                default: store
                }
            },
            verificationDelay: 0.01,
            runScript: { script in
                log.record(script)
                return true
            })
        return (store, global, centre, controller, { log.scripts })
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
        let (store, _, centre, controller) = makeSubjectWithBothMenuBarDomains()
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
            case .menuBarAutoHide: (centre, "AutoHideMenuBarOption", MenuBarAutoHide.always.optionValue)
            }
        edit.domain.set(edit.value, forKey: edit.key)

        let differences = controller.readSystemConfig().differences(from: DockConfiguration())

        #expect(differences.contains(property), "`\(edit.key)` is not read")
    }

    // MARK: - The Other Domain

    /// The popup's value is the setting; `_HIHideMenuBar` only does the hiding. Reading
    /// the wrong one of them is how a Dock profile came to disagree with the System
    /// Settings popup in both directions at once.
    @Test func theMenuBarComesFromThePopupsOwnDomain() {
        let (store, global, centre, controller) = makeSubjectWithBothMenuBarDomains()

        // Planted in the Dock's domain: must change nothing.
        store.set(MenuBarAutoHide.always.optionValue, forKey: "AutoHideMenuBarOption")
        #expect(controller.readSystemConfig().menuBarAutoHide == .inFullScreen)

        centre.set(MenuBarAutoHide.never.optionValue, forKey: "AutoHideMenuBarOption")
        #expect(controller.readSystemConfig().menuBarAutoHide == .never)

        // The popup wins over the hiding half, which macOS lets drift out of step.
        global.set(true, forKey: "_HIHideMenuBar")
        #expect(controller.readSystemConfig().menuBarAutoHide == .never, "the popup decides")
    }

    /// An account that has never touched the setting has neither key. Measured on one:
    /// the popup reads "In Full Screen Only".
    @Test func anUntouchedAccountReadsAsInFullScreenOnly() {
        let (_, _, _, controller) = makeSubjectWithBothMenuBarDomains()

        #expect(controller.readSystemConfig().menuBarAutoHide == .inFullScreen)
    }

    /// Before the popup's value existed we only had the hiding half. A profile read on
    /// a machine where something wrote that and nothing else still has to mean something.
    @Test func withoutThePopupValueTheHidingHalfDecides() {
        let (_, global, _, controller) = makeSubjectWithBothMenuBarDomains()

        global.set(true, forKey: "_HIHideMenuBar")

        #expect(controller.readSystemConfig().menuBarAutoHide == .always)
    }

    /// Applying has to move the popup's value too, or System Settings goes on showing
    /// the position the person had before while the menu bar behaves differently.
    @Test func applyingWritesThePopupsValue() {
        let (_, _, centre, controller) = makeSubjectWithBothMenuBarDomains()

        controller.apply(DockConfiguration(menuBarAutoHide: .onDesktop))

        #expect(
            centre.object(forKey: "AutoHideMenuBarOption") as? Int
                == MenuBarAutoHide.onDesktop.optionValue)
    }

    /// Every position maps to a distinct stored value, in the order System Settings
    /// lists them — the popup resolves a selection by index.
    @Test func everyPositionHasItsOwnOptionValue() {
        let values = MenuBarAutoHide.allCases.map(\.optionValue)

        #expect(values == [0, 1, 2, 3])
        #expect(Set(values).count == MenuBarAutoHide.allCases.count)
        for option in MenuBarAutoHide.allCases {
            #expect(MenuBarAutoHide(optionValue: option.optionValue) == option)
        }
    }

    /// A menu bar left hidden by the other half produces no difference against a profile
    /// that agrees with the popup — so without this it would stay hidden for good.
    @Test func applyReconcilesHalvesThatHaveFallenOutOfStep() {
        let (_, global, centre, controller, scripts) = makeSubjectRecordingScripts()
        centre.set(MenuBarAutoHide.inFullScreen.optionValue, forKey: "AutoHideMenuBarOption")
        global.set(true, forKey: "_HIHideMenuBar")  // hiding, though the popup says otherwise

        // Asks for exactly what the popup already reports, so nothing differs.
        controller.apply(DockConfiguration(menuBarAutoHide: .inFullScreen))

        #expect(
            scripts().contains { $0.contains("set autohide menu bar to false") },
            "the hiding half was left contradicting the popup: \(scripts())")
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

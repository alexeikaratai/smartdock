import Foundation
import Testing

@testable import SmartDockCore

/// Covers the settings store — everything the user configures passes through here.
///
/// Each test owns a `ScratchPreferences`, so nothing here shares state with any
/// other suite and the whole file runs in parallel.
@Suite("User preferences")
@MainActor
struct UserPreferencesTests {

    // MARK: - First Launch

    @Test func nothingIsConfiguredBeforeAnythingIsSaved() {
        let scratch = ScratchPreferences()

        #expect(!scratch.prefs.isConfigured)
    }

    @Test func savingTheExternalProfileCountsAsConfigured() {
        let scratch = ScratchPreferences()

        scratch.prefs.externalConfig = DockConfiguration(autohide: false)

        #expect(scratch.prefs.isConfigured)
    }

    @Test func savingTheBuiltinProfileCountsAsConfigured() {
        let scratch = ScratchPreferences()

        scratch.prefs.builtinConfig = DockConfiguration(autohide: true)

        #expect(scratch.prefs.isConfigured)
    }

    /// First launch turns the Dock as it is into both profiles — every field, so
    /// nothing changes until the person edits one. It used to force auto-hide on
    /// and off, which moved a Dock nobody had asked it to. Every field here is
    /// off its default, so a field that stopped being copied would show.
    @Test(arguments: DockProfile.allCases)
    func firstLaunchMakesEachProfileTheDockAsItIs(profile: DockProfile) {
        let scratch = ScratchPreferences()
        let system = DockConfiguration(
            autohide: true,
            position: .right,
            iconSize: DockConfiguration.pixelsToScale(64),
            magnification: true,
            magnificationSize: DockConfiguration.pixelsToScale(96),
            minimizeEffect: .scale,
            animatesLaunch: false,
            showsRecents: false,
            showsIndicators: false,
            minimizesToApplication: true)

        scratch.prefs.initializeDefaultsIfNeeded(from: system)

        #expect(scratch.prefs[profile] == system, "\(profile) must be the Dock verbatim, auto-hide included")
    }

    /// The guard that protects everything the user has configured. Without it, any
    /// later call would silently reset both profiles to the current system state.
    @Test func initializingAgainDoesNotOverwriteExistingSettings() {
        let scratch = ScratchPreferences()
        scratch.prefs.externalConfig = DockConfiguration(autohide: true, position: .left)

        scratch.prefs.initializeDefaultsIfNeeded(
            from: DockConfiguration(autohide: false, position: .bottom))

        #expect(scratch.prefs.externalConfig.autohide, "An existing profile must survive")
        #expect(scratch.prefs.externalConfig.position == .left)
    }

    // MARK: - Profiles

    @Test func profileSurvivesSaveAndLoad() {
        let scratch = ScratchPreferences()
        let config = DockConfiguration(
            autohide: true,
            position: .right,
            iconSize: DockConfiguration.pixelsToScale(72),
            magnification: true,
            magnificationSize: DockConfiguration.pixelsToScale(100))

        scratch.prefs.builtinConfig = config

        #expect(scratch.prefs.builtinConfig.approximatelyEquals(config))
    }

    /// Both size sliders reach 0.0 — `pixelsToScale(16)`, the smallest Dock macOS
    /// offers — and the loader used `value > 0` to spot an absent key. A deliberate
    /// minimum is indistinguishable from nothing that way, so it read back as our
    /// 48px default and the smallest Dock could not be kept. Whether someone chose
    /// a value is answered by the key being there, never by the value itself.
    @Test func theSmallestSizesSurviveSaveAndLoad() {
        let scratch = ScratchPreferences()
        let smallest = DockConfiguration.pixelsToScale(16)
        #expect(smallest == 0.0, "the slider's left edge really is zero")

        scratch.prefs.builtinConfig = DockConfiguration(
            iconSize: smallest, magnification: true, magnificationSize: smallest)

        #expect(scratch.prefs.builtinConfig.iconSize == smallest)
        #expect(scratch.prefs.builtinConfig.magnificationSize == smallest)
    }

    /// Every property survives a save and a load, one named at a time so a failure
    /// says which. Driven by `allCases`: saving and loading were two hand-written lists
    /// of ten fields before they shared one exhaustive switch, and a field missing from
    /// either was invisible — the form would just show the default on every open.
    @Test(arguments: DockProperty.allCases)
    func everyPropertySurvivesSaveAndLoad(property: DockProperty) {
        let scratch = ScratchPreferences()
        let changed = Self.flip(property, of: DockConfiguration(), to: Self.everythingChanged)

        scratch.prefs.builtinConfig = changed

        #expect(
            scratch.prefs.builtinConfig.describe(property) == changed.describe(property),
            "\(property) did not survive the round trip")
    }

    /// The stored key is built from `DockProperty.rawValue`, and these are the
    /// spellings already written on every installed machine. The raw values double as
    /// log and report text, so a rename to read better in a diagnostic would orphan
    /// real profiles — this cannot make that impossible, but it makes it deliberate:
    /// the switch is exhaustive, so a new property must state its on-disk spelling.
    @Test func storedKeysStillMatchTheirPropertyNames() {
        for property in DockProperty.allCases {
            let onDisk: String =
                switch property {
                case .position: "position"
                case .autohide: "autohide"
                case .iconSize: "iconSize"
                case .magnification: "magnification"
                case .magnificationSize: "magnificationSize"
                case .minimizeEffect: "minimizeEffect"
                case .animatesLaunch: "animatesLaunch"
                case .showsRecents: "showsRecents"
                case .showsIndicators: "showsIndicators"
                case .minimizesToApplication: "minimizesToApplication"
                }

            #expect(property.rawValue == onDisk, "renaming this orphans keys already on disk")
        }
    }

    @Test func minimizeEffectAndLaunchAnimationSurviveSaveAndLoad() {
        let scratch = ScratchPreferences()

        scratch.prefs.externalConfig = DockConfiguration(
            minimizeEffect: .scale, animatesLaunch: false, showsRecents: false,
            showsIndicators: false, minimizesToApplication: true)

        #expect(scratch.prefs.externalConfig.minimizeEffect == .scale)
        #expect(!scratch.prefs.externalConfig.animatesLaunch)
        #expect(!scratch.prefs.externalConfig.showsRecents)
        #expect(!scratch.prefs.externalConfig.showsIndicators)
        #expect(scratch.prefs.externalConfig.minimizesToApplication)
    }

    /// A profile written before these two settings existed has neither key. Reading
    /// `animatesLaunch` the way the other flags are read would answer `false`, and
    /// upgrading would silently switch launch animation off for everyone who had a
    /// saved profile — a change they never asked for, applied on the next refresh.
    @Test func aProfileSavedBeforeTheseSettingsKeepsTheDockDefaults() {
        let scratch = ScratchPreferences()

        // Exactly what an older build stored: the five original keys, nothing more.
        scratch.defaults.set(true, forKey: "com.smartdock.builtin.autohide")
        scratch.defaults.set("left", forKey: "com.smartdock.builtin.position")
        scratch.defaults.set(0.3, forKey: "com.smartdock.builtin.iconSize")
        scratch.defaults.set(false, forKey: "com.smartdock.builtin.magnification")
        scratch.defaults.set(0.43, forKey: "com.smartdock.builtin.magnificationSize")

        let loaded = scratch.prefs.builtinConfig

        #expect(loaded.position == .left, "the old keys still load")
        #expect(loaded.animatesLaunch, "launch animation must not be switched off by upgrading")
        #expect(loaded.showsRecents, "recents must not be switched off by upgrading")
        #expect(loaded.showsIndicators, "indicators must not be switched off by upgrading")
        #expect(!loaded.minimizesToApplication, "minimize-into-app must not be switched on by upgrading")
        #expect(loaded.minimizeEffect == .genie)
    }

    /// Upgrading must not quietly restyle the Dock. A profile saved before these
    /// settings existed loads them as struct defaults — genie, animation on — and
    /// applying it would push both at someone who had deliberately chosen Scale with
    /// animation off. Their own current Dock is the right source for a value the
    /// profile never recorded.
    @Test func backfillTakesMissingSettingsFromTheDockNotFromDefaults() {
        let scratch = ScratchPreferences()
        scratch.defaults.set(true, forKey: "com.smartdock.builtin.autohide")
        scratch.defaults.set("left", forKey: "com.smartdock.builtin.position")

        scratch.prefs.backfillMissingSettings(
            from: DockConfiguration(
                minimizeEffect: .scale, animatesLaunch: false,
                showsIndicators: false, minimizesToApplication: true))

        #expect(scratch.prefs.builtinConfig.minimizeEffect == .scale)
        #expect(!scratch.prefs.builtinConfig.animatesLaunch)
        #expect(!scratch.prefs.builtinConfig.showsIndicators, "their Dock, not our default")
        #expect(scratch.prefs.builtinConfig.minimizesToApplication, "their Dock, not our default")
        #expect(scratch.prefs.builtinConfig.position == .left, "existing settings untouched")
    }

    /// Only the absent keys are filled. A profile that already carries a choice must
    /// keep it, or every launch would overwrite the profile with the live Dock.
    @Test func backfillLeavesSettingsThatWereAlreadySaved() {
        let scratch = ScratchPreferences()
        scratch.prefs.builtinConfig = DockConfiguration(
            minimizeEffect: .genie, animatesLaunch: true)

        scratch.prefs.backfillMissingSettings(
            from: DockConfiguration(minimizeEffect: .scale, animatesLaunch: false))

        #expect(scratch.prefs.builtinConfig.minimizeEffect == .genie)
        #expect(scratch.prefs.builtinConfig.animatesLaunch)
    }

    @Test func backfillDoesNothingBeforeAnyProfileExists() {
        let scratch = ScratchPreferences()

        scratch.prefs.backfillMissingSettings(
            from: DockConfiguration(minimizeEffect: .scale, animatesLaunch: false))

        #expect(!scratch.prefs.isConfigured, "an unconfigured install is seeded by first launch")
    }

    @Test func theTwoProfilesAreStoredIndependently() {
        let scratch = ScratchPreferences()

        scratch.prefs.externalConfig = DockConfiguration(autohide: false, position: .bottom)
        scratch.prefs.builtinConfig = DockConfiguration(autohide: true, position: .left)

        #expect(!scratch.prefs.externalConfig.autohide)
        #expect(scratch.prefs.externalConfig.position == .bottom)
        #expect(scratch.prefs.builtinConfig.autohide)
        #expect(scratch.prefs.builtinConfig.position == .left)
    }

    /// Unset profiles must read as the sensible defaults the app was designed
    /// around, not as a zero-size Dock at the bottom of the screen.
    @Test func unsetProfilesFallBackToSensibleDefaults() {
        let scratch = ScratchPreferences()

        #expect(!scratch.prefs.externalConfig.autohide)
        #expect(scratch.prefs.builtinConfig.autohide)
    }

    // MARK: - Copying

    /// The guard against the bug that prompted `with` to exist: a call site that
    /// changes one property must not quietly reset the ones it does not mention.
    @Test func changingOnePropertyCarriesEveryOtherOneOver() {
        let original = DockConfiguration(
            autohide: false,
            position: .right,
            iconSize: DockConfiguration.pixelsToScale(72),
            magnification: true,
            magnificationSize: DockConfiguration.pixelsToScale(100),
            minimizeEffect: .scale,
            animatesLaunch: false)

        let toggled = original.with(autohide: true)

        #expect(toggled.autohide, "the one property asked for changed")
        #expect(toggled.position == original.position)
        #expect(toggled.magnification == original.magnification)
        #expect(toggled.minimizeEffect == .scale, "must not fall back to the struct default")
        #expect(!toggled.animatesLaunch, "must not fall back to the struct default")
        expectClose(toggled.iconSize, original.iconSize, within: 0.0001)
        expectClose(toggled.magnificationSize, original.magnificationSize, within: 0.0001)
    }

    /// Every field is deliberately set away from its default. Equality would other-
    /// wise pass for a `with` that dropped a property back to that default, which is
    /// exactly the failure this guards — and exactly what it missed when
    /// `showsRecents` was added while the fixture still left it at `true`.
    @Test func copyingNothingLeavesTheConfigurationUnchanged() {
        let original = DockConfiguration(
            autohide: true,
            position: .left,
            iconSize: DockConfiguration.pixelsToScale(72),
            magnification: true,
            magnificationSize: DockConfiguration.pixelsToScale(100),
            minimizeEffect: .scale,
            animatesLaunch: false,
            showsRecents: false,
            showsIndicators: false,
            minimizesToApplication: true)

        #expect(original.with() == original)
    }

    // MARK: - Flags

    /// The one flag that is **on** when its key is missing. Reading it like the
    /// others would silently disable System Settings sync for every existing user.
    @Test func syncFromSystemIsOnUntilExplicitlyDisabled() {
        let scratch = ScratchPreferences()

        #expect(scratch.prefs.syncFromSystemEnabled, "Absent key must mean enabled")

        scratch.prefs.syncFromSystemEnabled = false
        #expect(!scratch.prefs.syncFromSystemEnabled)

        scratch.prefs.syncFromSystemEnabled = true
        #expect(scratch.prefs.syncFromSystemEnabled)
    }

    @Test func flagsThatDefaultToOff() {
        let scratch = ScratchPreferences()

        #expect(!scratch.prefs.notificationsEnabled)
        #expect(!scratch.prefs.hasSeenOnboarding)
        #expect(!scratch.prefs.hasPromptedAccessibility)
        #expect(!scratch.prefs.pendingAccessibilityGrant)
    }

    @Test func flagsRoundTrip() {
        let scratch = ScratchPreferences()

        scratch.prefs.notificationsEnabled = true
        scratch.prefs.hasSeenOnboarding = true
        scratch.prefs.hasPromptedAccessibility = true
        scratch.prefs.pendingAccessibilityGrant = true

        #expect(scratch.prefs.notificationsEnabled)
        #expect(scratch.prefs.hasSeenOnboarding)
        #expect(scratch.prefs.hasPromptedAccessibility)
        #expect(scratch.prefs.pendingAccessibilityGrant)
    }

    // MARK: - Hotkeys

    /// Stored values that no longer decode fall back to the Dock's own defaults
    /// rather than refusing to load the profile — a renamed enum case must not
    /// wipe someone's settings.
    @Test func aProfileWithValuesThatNoLongerDecodeFallsBackToTheDockDefaults() {
        let scratch = ScratchPreferences()
        scratch.prefs.externalConfig = DockConfiguration(position: .left, minimizeEffect: .scale)
        scratch.defaults.set("diagonal", forKey: "com.smartdock.external.position")
        scratch.defaults.set("suck", forKey: "com.smartdock.external.minimizeEffect")

        let loaded = scratch.prefs.externalConfig

        #expect(loaded.position == .bottom)
        #expect(loaded.minimizeEffect == .genie)
    }

    @Test func aProfileMissingItsPositionKeyReadsAsBottom() {
        let scratch = ScratchPreferences()
        scratch.prefs.externalConfig = DockConfiguration(position: .right)
        scratch.defaults.removeObject(forKey: "com.smartdock.external.position")

        #expect(scratch.prefs.externalConfig.position == .bottom)
    }

    @Test func unboundActionHasNoBinding() {
        let scratch = ScratchPreferences()

        #expect(scratch.prefs.hotkey(for: "refreshNow") == nil)
    }

    @Test func bindingSurvivesSaveAndLoad() {
        let scratch = ScratchPreferences()
        let binding = HotkeyBinding(keyCode: 15, modifiers: 1_966_080, displayName: "R")

        scratch.prefs.setHotkey(binding, for: "refreshNow")

        #expect(scratch.prefs.hotkey(for: "refreshNow") == binding)
    }

    /// A binding whose display name was lost still fires; it just shows a
    /// placeholder until re-recorded.
    @Test func aBindingWithoutADisplayNameShowsAPlaceholder() {
        let scratch = ScratchPreferences()
        scratch.prefs.setHotkey(HotkeyBinding(keyCode: 15, modifiers: 1_966_080, displayName: "R"), for: "refreshNow")
        scratch.defaults.removeObject(forKey: "com.smartdock.hotkey.refreshNow.displayName")

        #expect(scratch.prefs.hotkey(for: "refreshNow")?.displayName == "?")
    }

    @Test func clearingABindingRemovesItEntirely() {
        let scratch = ScratchPreferences()
        scratch.prefs.setHotkey(
            HotkeyBinding(keyCode: 15, modifiers: 1_966_080, displayName: "R"), for: "refreshNow")

        scratch.prefs.setHotkey(nil, for: "refreshNow")

        #expect(scratch.prefs.hotkey(for: "refreshNow") == nil, "A cleared shortcut must not linger")
    }

    @Test func bindingsForDifferentActionsDoNotCollide() {
        let scratch = ScratchPreferences()

        scratch.prefs.setHotkey(
            HotkeyBinding(keyCode: 15, modifiers: 1_966_080, displayName: "R"), for: "refreshNow")
        scratch.prefs.setHotkey(
            HotkeyBinding(keyCode: 2, modifiers: 1_966_080, displayName: "D"), for: "toggleAutohide")

        #expect(scratch.prefs.hotkey(for: "refreshNow")?.displayName == "R")
        #expect(scratch.prefs.hotkey(for: "toggleAutohide")?.displayName == "D")
    }

    // MARK: - Migration

    /// Sizes used to be stored as pixels (16–128) and are now a 0.0–1.0 scale.
    /// Left unconverted, an old value reads as far past the maximum and every
    /// upgrading user gets the largest possible Dock icons.
    @Test func oldPixelSizesAreConvertedToScale() {
        let scratch = ScratchPreferences()
        scratch.defaults.set(64, forKey: "com.smartdock.external.iconSize")
        scratch.defaults.set(96, forKey: "com.smartdock.external.magnificationSize")

        scratch.prefs.migrateIfNeeded()

        expectClose(
            scratch.defaults.double(forKey: "com.smartdock.external.iconSize"),
            DockConfiguration.pixelsToScale(64))
        expectClose(
            scratch.defaults.double(forKey: "com.smartdock.external.magnificationSize"),
            DockConfiguration.pixelsToScale(96))
    }

    /// Migration must be idempotent — it runs on every launch, and a value already
    /// in scale form would otherwise be shrunk again each time.
    @Test func alreadyMigratedValuesAreLeftAlone() {
        let scratch = ScratchPreferences()
        let scale = DockConfiguration.pixelsToScale(64)
        scratch.defaults.set(scale, forKey: "com.smartdock.builtin.iconSize")

        scratch.prefs.migrateIfNeeded()
        scratch.prefs.migrateIfNeeded()

        expectClose(scratch.defaults.double(forKey: "com.smartdock.builtin.iconSize"), scale)
    }

    @Test(arguments: ["com.smartdock.external.iconSize", "com.smartdock.builtin.iconSize"])
    func migrationCoversBothProfiles(key: String) {
        let scratch = ScratchPreferences()
        scratch.defaults.set(48, forKey: key)

        scratch.prefs.migrateIfNeeded()

        #expect(scratch.defaults.double(forKey: key) <= 1.0, "\(key) is still in the old pixel format")
    }

    /// A stored `1` is ambiguous: one pixel in the old format, and the maximum on
    /// the new 0.0–1.0 scale. It has to be read as the scale — treating it as
    /// pixels would collapse the largest icons a user can pick into the smallest.
    @Test func aStoredOneIsTreatedAsMaximumScaleNotOnePixel() {
        let scratch = ScratchPreferences()
        scratch.defaults.set(1, forKey: "com.smartdock.external.iconSize")

        scratch.prefs.migrateIfNeeded()

        expectClose(
            scratch.defaults.double(forKey: "com.smartdock.external.iconSize"), 1.0,
            "Maximum scale was mistaken for a one-pixel icon")
    }

    /// The old format wrote sizes as `Int` from the slider but as `Double` once a
    /// value had round-tripped through the Dock. Both spellings have to migrate, or
    /// half the upgrading users keep a pixel value in a field that now means scale.
    @Test func oldPixelSizesStoredAsDoublesAreAlsoConverted() {
        let scratch = ScratchPreferences()
        scratch.defaults.set(64.0 as Double, forKey: "com.smartdock.external.iconSize")
        scratch.defaults.set(96.0 as Double, forKey: "com.smartdock.external.magnificationSize")

        scratch.prefs.migrateIfNeeded()

        expectClose(
            scratch.defaults.double(forKey: "com.smartdock.external.iconSize"),
            DockConfiguration.pixelsToScale(64))
        expectClose(
            scratch.defaults.double(forKey: "com.smartdock.external.magnificationSize"),
            DockConfiguration.pixelsToScale(96))
    }

    @Test func migrationOnAnUntouchedInstallDoesNothing() {
        let scratch = ScratchPreferences()

        scratch.prefs.migrateIfNeeded()

        #expect(!scratch.prefs.isConfigured)
    }

    // MARK: - Helpers

    /// Every field away from its default, so taking any single one of them is a real
    /// change and a property that failed to round-trip cannot look like a pass.
    private static let everythingChanged = DockConfiguration(
        autohide: true,
        position: .right,
        iconSize: DockConfiguration.pixelsToScale(96),
        magnification: true,
        magnificationSize: DockConfiguration.pixelsToScale(112),
        minimizeEffect: .scale,
        animatesLaunch: false,
        showsRecents: false,
        showsIndicators: false,
        minimizesToApplication: true)

    /// One property taken from `other`, the rest left at `base`.
    private static func flip(
        _ property: DockProperty, of base: DockConfiguration, to other: DockConfiguration
    ) -> DockConfiguration {
        switch property {
        case .position: base.with(position: other.position)
        case .autohide: base.with(autohide: other.autohide)
        case .iconSize: base.with(iconSize: other.iconSize)
        case .magnification: base.with(magnification: other.magnification)
        case .magnificationSize: base.with(magnificationSize: other.magnificationSize)
        case .minimizeEffect: base.with(minimizeEffect: other.minimizeEffect)
        case .animatesLaunch: base.with(animatesLaunch: other.animatesLaunch)
        case .showsRecents: base.with(showsRecents: other.showsRecents)
        case .showsIndicators: base.with(showsIndicators: other.showsIndicators)
        case .minimizesToApplication:
            base.with(minimizesToApplication: other.minimizesToApplication)
        }
    }
}

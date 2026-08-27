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

    /// First launch seeds both profiles from whatever the Dock already looks like,
    /// changing only autohide — so the user's Dock does not visibly jump the first
    /// time the app runs.
    @Test func firstLaunchSeedsBothProfilesFromTheSystem() {
        let scratch = ScratchPreferences()
        let system = DockConfiguration(
            autohide: false,
            position: .right,
            iconSize: DockConfiguration.pixelsToScale(64),
            magnification: true,
            magnificationSize: DockConfiguration.pixelsToScale(96))

        scratch.prefs.initializeDefaultsIfNeeded(from: system)

        for profile in [scratch.prefs.externalConfig, scratch.prefs.builtinConfig] {
            #expect(profile.position == .right)
            expectClose(profile.iconSize, system.iconSize)
            #expect(profile.magnification)
            expectClose(profile.magnificationSize, system.magnificationSize)
        }

        #expect(!scratch.prefs.externalConfig.autohide, "Dock stays visible with a monitor attached")
        #expect(scratch.prefs.builtinConfig.autohide, "Dock hides on the laptop screen alone")
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
}

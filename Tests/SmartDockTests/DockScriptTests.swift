import Foundation
import Testing

@testable import SmartDockCore

/// Covers the AppleScript each dock property is pushed with.
///
/// These strings are the actual instruction System Events receives. A typo in one
/// is invisible from inside the app: the script still runs, still reports success,
/// and the setting simply never changes — the exact failure mode that took a whole
/// debugging session to pin down for `autohide`. Only `screen edge` was exercised
/// before, because the verification tests happened to change position and nothing
/// else.
@Suite("Dock AppleScript")
@MainActor
struct DockScriptTests {

    /// A controller over an empty scratch domain, recording what it would send.
    /// An empty domain reads back as the macOS defaults, so a config differing in
    /// exactly one property produces exactly one script.
    private func makeRecorder(
        seed: [String: Any] = [:]
    ) -> (scripts: () -> [String], controller: DockController) {
        let store = InMemoryDefaults()
        for (key, value) in seed {
            store.set(value, forKey: key)
        }

        let box = ScriptLog()
        let controller = DockController(
            openDefaults: { store }, verificationDelay: 0.01,
            runScript: { script in
                box.record(script)
                // Keep the domain alive for as long as the controller is.
                _ = store
                return true

            })
        return ({ box.scripts }, controller)
    }

    /// Reference box so the recording closure and the test see the same array.
    private final class ScriptLog {
        private(set) var scripts: [String] = []
        func record(_ script: String) { scripts.append(script) }
    }

    // MARK: - Reading Absent Keys

    /// `launchanim` is missing on a fresh account, and `bool(forKey:)` answers false
    /// for a missing key — the opposite of what the Dock actually does.
    @Test func anAbsentLaunchAnimationKeyReadsAsOn() {
        let (_, controller) = makeRecorder()

        #expect(controller.readSystemConfig().animatesLaunch)
    }

    @Test func anAbsentMinimizeEffectKeyReadsAsGenie() {
        let (_, controller) = makeRecorder()

        #expect(controller.readSystemConfig().minimizeEffect == .genie)
    }

    @Test(arguments: [true, false])
    func aStoredLaunchAnimationIsReadBack(stored: Bool) {
        let (_, controller) = makeRecorder(seed: ["launchanim": stored])

        #expect(controller.readSystemConfig().animatesLaunch == stored)
    }

    @Test(arguments: MinimizeEffect.allCases)
    func aStoredMinimizeEffectIsReadBack(stored: MinimizeEffect) {
        let (_, controller) = makeRecorder(seed: ["mineffect": stored.rawValue])

        #expect(controller.readSystemConfig().minimizeEffect == stored)
    }

    // MARK: - One Property, One Script

    /// Every edge, not just one: the AppleScript enumerator is spelled per case,
    /// and a case that stopped matching would fail at run time only.
    @Test(arguments: DockPosition.allCases.filter { $0 != .bottom })
    func positionScriptSetsScreenEdge(position: DockPosition) {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(position: position))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set screen edge to \(position.rawValue)"))
    }

    /// `bottom` is the Dock's own default, so it is only ever *sent* when the
    /// Dock is somewhere else — seed the domain to make that so.
    @Test func bottomIsSentWhenTheDockIsElsewhere() {
        let (scripts, controller) = makeRecorder(seed: ["orientation": "left"])

        controller.apply(DockConfiguration(position: .bottom))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set screen edge to bottom"))
    }

    // MARK: - The Real Executor

    /// The one path that is not injected. A script that touches nothing proves the
    /// call works; a script that cannot compile proves an error comes back as
    /// `false` rather than a crash or a silent `true`.
    @Test func theRealExecutorRunsAScript() {
        #expect(DockController.executeAppleScript("return 1"))
    }

    @Test func theRealExecutorReportsAScriptError() {
        #expect(!DockController.executeAppleScript("this is not AppleScript"))
    }

    /// A refused script is reported, not swallowed. `NSAppleScript` says nothing
    /// about whether the Dock honoured it, but a script that would not even run
    /// is a failure `apply` can and does report.
    @Test func aFailedScriptMakesApplyReportFailure() {
        let store = InMemoryDefaults()
        let controller = DockController(
            openDefaults: { store }, verificationDelay: 0.01, runScript: { _ in false })

        #expect(!controller.apply(DockConfiguration(autohide: true)))
    }

    @Test func autohideScriptSetsAutohide() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(autohide: true))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set autohide to true"))
    }

    @Test func minimizeEffectScriptSetsTheEffect() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(minimizeEffect: .scale))

        #expect(scripts().count == 1)
        // Unquoted on purpose — an AppleScript enumerator, not a string.
        #expect(scripts()[0].contains("set minimize effect to scale"), "\(scripts())")
    }

    @Test func showRecentsScriptSetsShowRecents() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(showsRecents: false))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set show recents to false"), "\(scripts())")
    }

    /// macOS ships with recents **on** and writes the key only once it is turned
    /// off, so a missing key must read as `true` — otherwise every apply pushes a
    /// script to re-enable something that was never off.
    @Test func anAbsentShowRecentsKeyReadsAsOn() {
        let (_, controller) = makeRecorder()

        #expect(controller.readSystemConfig().showsRecents)
    }

    @Test(arguments: [true, false])
    func aStoredShowRecentsIsReadBack(stored: Bool) {
        let (_, controller) = makeRecorder(seed: ["show-recents": stored])

        #expect(controller.readSystemConfig().showsRecents == stored)
    }

    @Test func showIndicatorsScriptSetsShowIndicators() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(showsIndicators: false))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set show indicators to false"), "\(scripts())")
    }

    @Test func minimizeToApplicationScriptSetsMinimizeIntoApplication() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(minimizesToApplication: true))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set minimize into application to true"), "\(scripts())")
    }

    /// Measured with the keys deleted: System Events reports indicators on and
    /// minimize-into-application off. A missing key must read the same way, or every
    /// apply would push a script for a setting nobody changed.
    @Test func absentIndicatorAndMinimizeKeysReadAsTheMacOSDefaults() {
        let (_, controller) = makeRecorder()

        #expect(controller.readSystemConfig().showsIndicators)
        #expect(!controller.readSystemConfig().minimizesToApplication)
    }

    @Test(arguments: [true, false])
    func storedIndicatorAndMinimizeKeysAreReadBack(stored: Bool) {
        let (_, controller) = makeRecorder(
            seed: ["show-process-indicators": stored, "minimize-to-application": stored])

        #expect(controller.readSystemConfig().showsIndicators == stored)
        #expect(controller.readSystemConfig().minimizesToApplication == stored)
    }

    @Test func launchAnimationScriptSetsAnimate() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(animatesLaunch: false))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set animate to false"), "\(scripts())")
    }

    /// The defaults in `DockConfiguration` have to match what macOS holds when the
    /// keys are absent, which is the normal state — neither `mineffect` nor
    /// `launchanim` is written until the setting is changed. Get either wrong and
    /// every single apply pushes a redundant script and flashes the Dock.
    @Test func aDefaultConfigAsksTheDockForNothing() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration())

        #expect(scripts().isEmpty, "\(scripts())")
    }

    @Test func iconSizeScriptSetsDockSize() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(iconSize: DockConfiguration.pixelsToScale(96)))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set dock size to"), "\(scripts())")
    }

    @Test func magnificationScriptSetsMagnification() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(magnification: true, magnificationSize: 0.4286))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set magnification to true"))
    }

    /// Magnified size is only pushed while magnification is already on, so the
    /// domain has to be seeded with it to isolate this property.
    @Test func magnificationSizeScriptSetsMagnificationSize() {
        let (scripts, controller) = makeRecorder(seed: [
            "magnification": true,
            "largesize": 64,
        ])

        controller.apply(
            DockConfiguration(
                magnification: true,
                magnificationSize: DockConfiguration.pixelsToScale(120)))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set magnification size to"), "\(scripts())")
    }

    // MARK: - Script Shape

    /// Every property goes in its own `tell` block on purpose: if System Events
    /// refuses one, the others still land. Bundling them would make a single
    /// rejected setting take the whole profile down with it.
    @Test func eachChangedPropertyIsSentAsItsOwnScript() {
        let (scripts, controller) = makeRecorder()

        controller.apply(
            DockConfiguration(
                autohide: true,
                position: .right,
                iconSize: DockConfiguration.pixelsToScale(96),
                magnification: true,
                magnificationSize: 0.4286))

        #expect(scripts().count == 4, "position, autohide, size and magnification are four writes")
        for script in scripts() {
            #expect(
                script.components(separatedBy: "set ").count == 2,
                "A script that sets two properties loses the others when one is refused")
        }
    }

    @Test func everyScriptTargetsDockPreferencesThroughSystemEvents() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(autohide: true, position: .left))

        #expect(!scripts().isEmpty)
        for script in scripts() {
            #expect(script.contains("tell application \"System Events\""))
            #expect(script.contains("tell dock preferences"))
        }
    }

    /// The diff decides what to send; this pins that nothing is sent when the Dock
    /// already matches. Without it a regression would show up only as a flicker.
    @Test func aMatchingConfigSendsNothing() {
        let (scripts, controller) = makeRecorder(seed: [
            "autohide": true,
            "orientation": "left",
            "tilesize": 48,
        ])

        controller.apply(
            DockConfiguration(
                autohide: true,
                position: .left,
                iconSize: DockConfiguration.pixelsToScale(48)))

        #expect(scripts().isEmpty)
    }
}

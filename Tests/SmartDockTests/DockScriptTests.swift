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

    // MARK: - One Property, One Script

    @Test func positionScriptSetsScreenEdge() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(position: .left))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set screen edge to left"))
    }

    @Test func autohideScriptSetsAutohide() {
        let (scripts, controller) = makeRecorder()

        controller.apply(DockConfiguration(autohide: true))

        #expect(scripts().count == 1)
        #expect(scripts()[0].contains("set autohide to true"))
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

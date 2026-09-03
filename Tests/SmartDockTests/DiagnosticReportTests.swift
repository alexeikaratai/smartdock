import Foundation
import Testing

@testable import SmartDockCore

@Suite("Diagnostic report")
struct DiagnosticReportTests {

    // MARK: - Helpers

    private func makeReport(
        isAccessibilityGranted: Bool = true,
        externalDisplayCount: Int = 1,
        hasExternalDisplay: Bool = true,
        externalConfig: DockConfiguration = DockConfiguration(autohide: false, position: .bottom),
        builtinConfig: DockConfiguration = DockConfiguration(autohide: true, position: .left),
        notificationsEnabled: Bool = true,
        syncFromSystemEnabled: Bool = true,
        hotkeys: [DiagnosticReport.Hotkey] = [],
        lastApplyOutcome: DockApplyOutcome? = nil
    ) -> DiagnosticReport {
        DiagnosticReport(
            appVersion: "2.0.1",
            buildNumber: "6",
            systemVersion: "Version 14.5 (Build 23F79)",
            isAccessibilityGranted: isAccessibilityGranted,
            externalDisplayCount: externalDisplayCount,
            hasExternalDisplay: hasExternalDisplay,
            externalConfig: externalConfig,
            builtinConfig: builtinConfig,
            notificationsEnabled: notificationsEnabled,
            syncFromSystemEnabled: syncFromSystemEnabled,
            hotkeys: hotkeys,
            lastApplyOutcome: lastApplyOutcome
        )
    }

    // MARK: - Apply Outcome

    /// Before the first apply there is nothing to say, and an empty line would just
    /// read as a missing value to whoever is triaging the report.
    @Test func unverifiedApplyIsOmittedEntirely() {
        #expect(!makeReport(lastApplyOutcome: nil).formatted.contains("Last apply"))
    }

    @Test func successfulApplyIsReported() {
        let output = makeReport(
            lastApplyOutcome: DockApplyOutcome(requested: [.position], rejected: [])
        ).formatted

        #expect(output.contains("Last apply"))
        #expect(output.contains("position"))
        #expect(!output.contains("⚠️"), "A clean apply should not be flagged")
    }

    /// The whole reason this field is in the report: a setting the Dock refused
    /// looks exactly like a working app from the user's side, so it has to stand
    /// out in a pasted issue the way a missing permission does.
    @Test func refusedApplyIsFlagged() {
        let output = makeReport(
            lastApplyOutcome: DockApplyOutcome(requested: [.autohide], rejected: [.autohide])
        ).formatted

        #expect(output.contains("ignored"), "\(output)")
        #expect(output.contains("autohide"))
        #expect(output.contains("⚠️"), "A refused setting must be visually obvious")
    }

    // MARK: - Identity

    @Test func reportIncludesVersionAndBuild() {
        let output = makeReport().formatted

        #expect(output.contains("SmartDock 2.0.1"))
        #expect(output.contains("build 6"))
    }

    @Test func reportIncludesSystemVersion() {
        #expect(makeReport().formatted.contains("14.5"))
    }

    // MARK: - Permission State

    @Test func grantedAccessibilityIsReported() {
        #expect(makeReport(isAccessibilityGranted: true).formatted.contains("Accessibility: granted"))
    }

    /// The single most common cause of "hotkeys don't work" — it must stand out.
    @Test func missingAccessibilityIsCalledOut() {
        #expect(
            makeReport(isAccessibilityGranted: false).formatted.contains("NOT granted"),
            "A missing grant should be visually obvious in a pasted report")
    }

    // MARK: - Display State

    @Test(arguments: [(true, "External Monitor"), (false, "Built-in Only")])
    func activeProfileReflectsExternalDisplay(hasExternal: Bool, label: String) {
        #expect(makeReport(hasExternalDisplay: hasExternal).formatted.contains("Active profile: \(label)"))
    }

    @Test(arguments: [0, 1, 2])
    func displayCountIsReported(count: Int) {
        #expect(makeReport(externalDisplayCount: count).formatted.contains("External displays: \(count)"))
    }

    // MARK: - Profiles

    @Test func profileDescribesEveryDockSetting() {
        let config = DockConfiguration(
            autohide: true,
            position: .right,
            iconSize: DockConfiguration.pixelsToScale(48),
            magnification: true,
            magnificationSize: DockConfiguration.pixelsToScale(96),
            minimizeEffect: .scale,
            animatesLaunch: false
        )

        let output = makeReport(externalConfig: config).formatted

        #expect(output.contains("right"))
        #expect(output.contains("auto-hide"))
        #expect(output.contains("48px"))
        #expect(output.contains("magnify 96px"))
        // A setting the profile applies but the report omits leaves the reader of a
        // bug report unable to account for what the Dock is doing.
        #expect(output.contains("scale"), "\(output)")
        #expect(output.contains("no launch animation"), "\(output)")
    }

    @Test func magnificationOffIsStated() {
        let config = DockConfiguration(autohide: false, position: .bottom, magnification: false)

        #expect(makeReport(externalConfig: config).formatted.contains("no magnification"))
    }

    @Test func alwaysVisibleIsStatedWhenAutohideOff() {
        let config = DockConfiguration(autohide: false, position: .bottom)

        #expect(makeReport(externalConfig: config).formatted.contains("always visible"))
    }

    // MARK: - Shortcuts

    @Test func unboundShortcutIsShownAsNotSet() {
        let hotkeys = [DiagnosticReport.Hotkey(action: "Refresh Now", shortcut: nil)]

        #expect(makeReport(hotkeys: hotkeys).formatted.contains("Refresh Now: not set"))
    }

    @Test func boundShortcutIsShown() {
        let hotkeys = [DiagnosticReport.Hotkey(action: "Refresh Now", shortcut: "⌃⌥R")]

        #expect(makeReport(hotkeys: hotkeys).formatted.contains("Refresh Now: ⌃⌥R"))
    }

    @Test func emptyShortcutListSaysSo() {
        #expect(makeReport(hotkeys: []).formatted.contains("none configured"))
    }

    // MARK: - Privacy

    /// The report is pasted into public issue trackers, so it must stay free of
    /// anything identifying. This guards against a field being added carelessly.
    @Test(arguments: ["/users/", "@", "serial", "uuid", "hostname"])
    func reportContainsNoIdentifyingInformation(leak: String) {
        let output = makeReport(
            hotkeys: [DiagnosticReport.Hotkey(action: "Refresh Now", shortcut: "⌃⌥R")]
        ).formatted.lowercased()

        #expect(!output.contains(leak), "Diagnostic report must not contain \"\(leak)\"")
    }

    /// Separate from the fixed markers above because the check only means anything
    /// when the account name is distinctive — a two-letter username would collide
    /// with ordinary words in the report and fail for no reason.
    @Test(.enabled(if: NSUserName().count >= 5, "Account name is too short to test against report prose"))
    func reportDoesNotLeakTheAccountName() {
        let output = makeReport().formatted.lowercased()

        #expect(
            !output.contains(NSUserName().lowercased()),
            "A home-directory path or user field must never reach the report")
    }
}

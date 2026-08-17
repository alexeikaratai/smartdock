import XCTest

@testable import SmartDockCore

final class DiagnosticReportTests: XCTestCase {

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
    func testUnverifiedApplyIsOmittedEntirely() {
        XCTAssertFalse(makeReport(lastApplyOutcome: nil).formatted.contains("Last apply"))
    }

    func testSuccessfulApplyIsReported() {
        let outcome = DockApplyOutcome(requested: [.position], rejected: [])
        let output = makeReport(lastApplyOutcome: outcome).formatted

        XCTAssertTrue(output.contains("Last apply"))
        XCTAssertTrue(output.contains("position"))
        XCTAssertFalse(output.contains("⚠️"), "A clean apply should not be flagged")
    }

    /// The whole reason this field is in the report: a setting the Dock refused
    /// looks exactly like a working app from the user's side, so it has to stand
    /// out in a pasted issue the way a missing permission does.
    func testRefusedApplyIsFlagged() {
        let outcome = DockApplyOutcome(requested: [.autohide], rejected: [.autohide])
        let output = makeReport(lastApplyOutcome: outcome).formatted

        XCTAssertTrue(output.contains("ignored"), output)
        XCTAssertTrue(output.contains("autohide"))
        XCTAssertTrue(output.contains("⚠️"), "A refused setting must be visually obvious")
    }

    // MARK: - Identity

    func testReportIncludesVersionAndBuild() {
        let output = makeReport().formatted
        XCTAssertTrue(output.contains("SmartDock 2.0.1"))
        XCTAssertTrue(output.contains("build 6"))
    }

    func testReportIncludesSystemVersion() {
        XCTAssertTrue(makeReport().formatted.contains("14.5"))
    }

    // MARK: - Permission State

    func testGrantedAccessibilityIsReported() {
        XCTAssertTrue(makeReport(isAccessibilityGranted: true).formatted.contains("Accessibility: granted"))
    }

    /// The single most common cause of "hotkeys don't work" — it must stand out.
    func testMissingAccessibilityIsCalledOut() {
        let output = makeReport(isAccessibilityGranted: false).formatted
        XCTAssertTrue(
            output.contains("NOT granted"),
            "A missing grant should be visually obvious in a pasted report")
    }

    // MARK: - Display State

    func testActiveProfileReflectsExternalDisplay() {
        XCTAssertTrue(
            makeReport(hasExternalDisplay: true).formatted
                .contains("Active profile: External Monitor"))
        XCTAssertTrue(
            makeReport(hasExternalDisplay: false).formatted
                .contains("Active profile: Built-in Only"))
    }

    func testDisplayCountIsReported() {
        XCTAssertTrue(makeReport(externalDisplayCount: 2).formatted.contains("External displays: 2"))
        XCTAssertTrue(makeReport(externalDisplayCount: 0).formatted.contains("External displays: 0"))
    }

    // MARK: - Profiles

    func testProfileDescribesEveryDockSetting() {
        let config = DockConfiguration(
            autohide: true,
            position: .right,
            iconSize: DockConfiguration.pixelsToScale(48),
            magnification: true,
            magnificationSize: DockConfiguration.pixelsToScale(96)
        )
        let output = makeReport(externalConfig: config).formatted

        XCTAssertTrue(output.contains("right"))
        XCTAssertTrue(output.contains("auto-hide"))
        XCTAssertTrue(output.contains("48px"))
        XCTAssertTrue(output.contains("magnify 96px"))
    }

    func testMagnificationOffIsStated() {
        let config = DockConfiguration(autohide: false, position: .bottom, magnification: false)
        XCTAssertTrue(makeReport(externalConfig: config).formatted.contains("no magnification"))
    }

    func testAlwaysVisibleIsStatedWhenAutohideOff() {
        let config = DockConfiguration(autohide: false, position: .bottom)
        XCTAssertTrue(makeReport(externalConfig: config).formatted.contains("always visible"))
    }

    // MARK: - Shortcuts

    func testUnboundShortcutIsShownAsNotSet() {
        let hotkeys = [DiagnosticReport.Hotkey(action: "Refresh Now", shortcut: nil)]
        XCTAssertTrue(makeReport(hotkeys: hotkeys).formatted.contains("Refresh Now: not set"))
    }

    func testBoundShortcutIsShown() {
        let hotkeys = [DiagnosticReport.Hotkey(action: "Refresh Now", shortcut: "⌃⌥R")]
        XCTAssertTrue(makeReport(hotkeys: hotkeys).formatted.contains("Refresh Now: ⌃⌥R"))
    }

    func testEmptyShortcutListSaysSo() {
        XCTAssertTrue(makeReport(hotkeys: []).formatted.contains("none configured"))
    }

    // MARK: - Privacy

    /// The report is pasted into public issue trackers, so it must stay free of
    /// anything identifying. This guards against a field being added carelessly.
    func testReportContainsNoIdentifyingInformation() {
        let output = makeReport(
            hotkeys: [DiagnosticReport.Hotkey(action: "Refresh Now", shortcut: "⌃⌥R")]
        ).formatted.lowercased()

        for leak in ["/users/", "@", "serial", "uuid", "hostname"] {
            XCTAssertFalse(
                output.contains(leak),
                "Diagnostic report must not contain \"\(leak)\"")
        }
    }

    /// Separate from the fixed markers above because the check only means
    /// anything when the account name is distinctive — a two-letter username
    /// would collide with ordinary words in the report and fail for no reason.
    func testReportDoesNotLeakTheAccountName() throws {
        let username = NSUserName().lowercased()
        try XCTSkipUnless(
            username.count >= 5,
            "Account name \"\(username)\" is too short to test against report prose")

        let output = makeReport().formatted.lowercased()
        XCTAssertFalse(
            output.contains(username),
            "A home-directory path or user field must never reach the report")
    }
}

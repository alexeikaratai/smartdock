import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

// The smaller views and the wrappers around system services. Each is built for real
// and read back; the actions that would leave the test process — opening a URL,
// registering a login item, resetting a permission — are the ones left alone.

// MARK: - General Tab

@Suite("General tab")
@MainActor
struct GeneralTabViewTests {

    /// A login item that records instead of registering — the real one would put
    /// `xctest` in the developer's Login Items.
    @MainActor
    final class FakeLoginItem: LoginItemRegistering {
        var isRegistered = false
        private(set) var changes = 0

        func register() throws {
            changes += 1
            isRegistered = true
        }

        func unregister() throws {
            changes += 1
            isRegistered = false
        }
    }

    @MainActor
    private struct Fixture {
        let scratch = ScratchPreferences()
        let dock = MockDockController()
        let loginItem = FakeLoginItem()
        let service: SmartDockService
        let view: GeneralTabView

        init() {
            service = SmartDockService(
                displayMonitor: MockDisplayMonitor(), dockController: dock, prefs: scratch.prefs)
            service.start()
            scratch.prefs.notificationsEnabled = true
            scratch.prefs.syncFromSystemEnabled = false
            view = GeneralTabView(
                service: service, prefs: scratch.prefs,
                launchAtLogin: LaunchAtLogin(service: loginItem))
        }
    }

    @Test func checkboxesShowTheStoredFlags() {
        let f = Fixture()

        #expect(f.view.notificationsCheckbox.state == .on)
        #expect(f.view.syncFromSystemCheckbox.state == .off)
        #expect(f.view.launchAtLoginCheckbox.state == .off, "the fake login item is not registered")
    }

    @Test func togglingLaunchAtLoginRegistersAndFollowsTheResult() {
        let f = Fixture()

        f.view.launchAtLoginCheckbox.performClick(nil)

        #expect(f.loginItem.isRegistered)
        #expect(f.view.launchAtLoginCheckbox.state == .on)

        f.view.launchAtLoginCheckbox.performClick(nil)

        #expect(!f.loginItem.isRegistered)
        #expect(f.view.launchAtLoginCheckbox.state == .off)
    }

    @Test func togglingSyncWritesTheFlag() {
        let f = Fixture()

        f.view.syncFromSystemCheckbox.performClick(nil)

        #expect(f.scratch.prefs.syncFromSystemEnabled)
    }

    /// Ticking notifications also asks for authorisation — that is the manager's
    /// job, reached through a notification so the view never touches `UNUserNotificationCenter`.
    @Test func tickingNotificationsWritesTheFlagAndAsksForAuthorisation() {
        let f = Fixture()
        f.scratch.prefs.notificationsEnabled = false
        f.view.notificationsCheckbox.state = .off
        let asked = Tally()
        let token = NotificationCenter.default.addObserver(
            forName: .smartDockRequestNotificationAuth, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { asked.count += 1 } }
        defer { NotificationCenter.default.removeObserver(token) }

        f.view.notificationsCheckbox.performClick(nil)

        #expect(f.scratch.prefs.notificationsEnabled)
        #expect(asked.count == 1)
    }

    /// Authorisation refused after the box was ticked turns the flag off; the box follows.
    @Test func aRefusedAuthorisationUnticksTheBox() {
        let f = Fixture()
        #expect(f.view.notificationsCheckbox.state == .on)

        f.scratch.prefs.notificationsEnabled = false
        NotificationCenter.default.post(name: .smartDockNotificationPermissionChanged, object: nil)

        #expect(f.view.notificationsCheckbox.state == .off)
    }

    @Test func refreshNowReappliesTheProfile() {
        let f = Fixture()
        let applies = f.dock.applyCallCount

        f.view.refreshButton.performClick(nil)

        #expect(f.dock.applyCallCount == applies + 1)
    }
}

// MARK: - About Tab

@Suite("About tab")
@MainActor
struct AboutTabViewTests {

    @Test func copyDiagnosticInfoPutsTheReportOnThePasteboard() {
        let scratch = ScratchPreferences()
        let service = SmartDockService(
            displayMonitor: MockDisplayMonitor(), dockController: MockDockController(), prefs: scratch.prefs)
        service.start()
        let view = AboutTabView(service: service, prefs: scratch.prefs)
        NSPasteboard.general.clearContents()

        view.copyButton.performClick(nil)

        let copied = NSPasteboard.general.string(forType: .string) ?? ""
        #expect(copied.contains("**SmartDock"))
        #expect(copied.contains("Active profile:"))
        #expect(copied.contains("**Profiles**"))
        #expect(view.copyButton.title.hasPrefix("Copied"))
    }

    /// The confirmation is temporary — the button goes back to inviting a copy,
    /// or a second bug report would be filed from a button that still says "Copied".
    @Test func theCopyConfirmationFadesBackToTheInvitation() async throws {
        let scratch = ScratchPreferences()
        let service = SmartDockService(
            displayMonitor: MockDisplayMonitor(), dockController: MockDockController(), prefs: scratch.prefs)
        let view = AboutTabView(service: service, prefs: scratch.prefs)

        view.copyButton.performClick(nil)
        try await waitUntil { view.copyButton.title == "Copy Diagnostic Info" }

        #expect(view.copyButton.title == "Copy Diagnostic Info")
    }
}

// MARK: - Accessibility Warning

@Suite("Accessibility warning")
@MainActor
struct AccessibilityWarningViewTests {

    /// The test process is never trusted, so the banner shows — the view follows
    /// `AccessibilityChecker.isGranted` rather than assuming either way.
    @Test func theBannerFollowsTheGrant() {
        let view = AccessibilityWarningView(prefs: ScratchPreferences().prefs)

        #expect(view.isHidden == AccessibilityChecker.isGranted)
        #expect(!AccessibilityChecker.isGranted, "a test bundle has no Accessibility grant")
    }
}

// MARK: - Position Picker & Icons

@Suite("Position picker")
@MainActor
struct PositionPickerTests {

    private func button(for position: DockPosition, in picker: PositionPicker) -> NSButton? {
        picker.arrangedSubviews.compactMap { $0 as? NSButton }.first {
            $0.tag == DockPosition.allCases.firstIndex(of: position)
        }
    }

    @Test func oneButtonPerPosition() {
        let picker = PositionPicker()

        #expect(picker.arrangedSubviews.compactMap { $0 as? NSButton }.count == DockPosition.allCases.count)
    }

    @Test(arguments: DockPosition.allCases)
    func tappingAButtonSelectsAndReports(position: DockPosition) throws {
        let picker = PositionPicker()
        var reported: [DockPosition] = []
        picker.onSelectionChange = { reported.append($0) }

        try #require(button(for: position, in: picker)).performClick(nil)

        #expect(picker.selectedPosition == position)
        #expect(reported == [position])
    }

    /// A programmatic load must not read as a tap — the host would mark a draft dirty.
    @Test func settingTheSelectionDoesNotReport() {
        let picker = PositionPicker()
        var reported = 0
        picker.onSelectionChange = { _ in reported += 1 }

        picker.selectedPosition = .right

        #expect(picker.selectedPosition == .right)
        #expect(reported == 0)
    }
}

@Suite("Position icons")
@MainActor
struct PositionIconTests {

    @Test(arguments: DockPosition.allCases, [true, false])
    func everyIconIsDrawnOnceAndCached(position: DockPosition, selected: Bool) {
        let first = PositionIcon.image(for: position, selected: selected)
        let second = PositionIcon.image(for: position, selected: selected)

        #expect(first.size.width > 0 && first.size.height > 0)
        #expect(first === second, "the same instance comes back")
        #expect(first.tiffRepresentation != nil, "rendering runs the drawing handler")
    }

    @Test func selectedAndUnselectedDiffer() {
        #expect(PositionIcon.image(for: .left, selected: true) !== PositionIcon.image(for: .left, selected: false))
    }
}

// MARK: - Factories

@Suite("UI factories")
@MainActor
struct UIFactoryTests {

    @Test func labelIsStaticText() {
        let label = UI.label("Hello", font: .systemFont(ofSize: 12))

        #expect(label.stringValue == "Hello")
        #expect(!label.isEditable && !label.isBordered)
        #expect(!label.translatesAutoresizingMaskIntoConstraints)
    }

    @Test func checkboxAndButtonCarryTheirAction() {
        let target = NSObject()
        let checkbox = UI.checkbox("Tick", target: target, action: #selector(NSObject.description as () -> String))
        let button = UI.smallButton("Go", target: target, action: #selector(NSObject.description as () -> String))

        #expect(checkbox.title == "Tick" && checkbox.target === target)
        #expect(button.title == "Go" && button.target === target)
    }

    /// Sliders cover the 0–1 scale the Dock uses and report continuously, so the
    /// pixel label can follow the thumb.
    @Test func scaleSliderSpansTheDockScale() {
        let slider = UI.scaleSlider(
            value: 0.5, target: NSObject(), action: #selector(NSObject.description as () -> String))

        #expect(slider.minValue == 0 && slider.maxValue == 1)
        #expect(slider.doubleValue == 0.5)
        #expect(slider.isContinuous)
    }

    @Test func glassCardAndWindowAreBuiltToBeFilled() {
        let card = UI.glassCard()
        #expect(card.material == .popover)

        let (window, content) = UI.glassWindow(
            title: "T", size: NSSize(width: 300, height: 200), styleMask: [.titled])
        #expect(window.title == "T")
        #expect(content.superview != nil, "the content view sits inside the window's glass")
        window.close()
    }
}

// MARK: - Onboarding

@Suite("Onboarding")
@MainActor
struct OnboardingWindowTests {

    @Test func getStartedFinishesAndRemembers() throws {
        _ = NSApplication.shared
        let scratch = ScratchPreferences()
        let onboarding = OnboardingWindow(prefs: scratch.prefs)
        var completed = 0
        onboarding.onComplete = { completed += 1 }

        onboarding.show()
        let startButton = try #require(
            onboarding.window?.contentView?.descendants.compactMap { $0 as? NSButton }.first {
                $0.title == "Get Started"
            })
        startButton.performClick(nil)

        #expect(completed == 1)
        #expect(scratch.prefs.hasSeenOnboarding)
    }
}

/// Main-actor box a `@Sendable` observer can bump.
@MainActor
private final class Tally {
    var count = 0
}

extension NSView {
    /// Every view below this one, depth first — for finding a control by title.
    fileprivate var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}

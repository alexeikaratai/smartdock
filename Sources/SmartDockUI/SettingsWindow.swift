import Cocoa
import SmartDockCore
import SwiftUI

/// Settings window for SmartDock.
/// Three tabs: Settings (dock config + general), Shortcuts (hotkey bindings), About.
///
/// The self-contained pieces live in their own types: `PositionPicker`,
/// `AccessibilityStatusView`, `AboutTabView`, `HotkeyRecorder`.
@MainActor
public final class SettingsWindow: NSObject {

    // MARK: - Types

    /// Raw values are the segment indices of `tabControl` — the two are read off each
    /// other in `selectTab` and `tabChanged`, so they have to stay in the same order.
    public enum Tab: Int, Sendable, CaseIterable {
        case dock = 0
        case general = 1
        case shortcuts = 2
        case about = 3

        /// The segment's words. They used to be a literal array beside this enum —
        /// two lists for one set of tabs, and `allCases` now drives the control, so a
        /// fifth tab cannot appear in one and not the other.
        var title: String {
            switch self {
            case .dock: "Dock"
            case .general: "General"
            case .shortcuts: "Shortcuts"
            case .about: "About"
            }
        }
    }

    typealias Mode = DockTabModel.Mode

    // MARK: - Properties

    // Internal rather than private so a test can reach the window and its tabs.
    var window: NSWindow?
    private var keyMonitor: Any?
    private let service: SmartDockService
    let hotkeyRecorder: HotkeyRecorder
    private let prefs: UserPreferences
    /// Apply / Discard / Cancel for a draft about to be lost — an `NSAlert` in the app,
    /// injectable because a modal alert cannot be answered from a test.
    private let decideDraft: @MainActor (Mode) -> DraftDecision

    private(set) var currentTab: Tab = .dock
    private(set) var selectedMode: Mode = .external

    // Controls — Top-level
    private var headerIconView: NSImageView!
    /// Held because the layout pass places them; nothing else reads either one.
    private var headerNameLabel: NSTextField!
    private var headerVersionLabel: NSTextField!
    /// The gutter every top-level row shares.
    private static let margin: CGFloat = 24
    var tabControl: NSSegmentedControl!
    /// The Dock tab is SwiftUI inside an `NSHostingView`; the model carries the
    /// state the window reads and writes, and the hosting view does not own it.
    var dockTab: DockTabModel!
    var dockContainer: NSView!
    var settingsScroll: NSScrollView!
    /// The General tab is SwiftUI inside an `NSHostingView`; the model is held
    /// separately because the hosting view does not own it.
    var generalModel: GeneralSettingsModel!
    var generalContainer: NSView!
    /// The Shortcuts tab is SwiftUI inside an `NSHostingView`.
    var shortcutsModel: ShortcutsModel!
    var accessibilityStatus: AccessibilityStatusModel!
    var shortcutsContainer: NSView!
    /// The About tab is SwiftUI inside an `NSHostingView`; the model is held
    /// separately because the hosting view does not own it.
    var aboutModel: AboutModel!
    var aboutContainer: NSView!

    // Controls — Settings tab

    // Controls — Shortcuts tab

    // MARK: - Init

    /// Whether Accessibility is already granted, which decides if the Shortcuts tab
    /// carries its warning banner. A parameter because the answer differs between this
    /// machine and a CI runner, and because the tab's layout in the *granted* case —
    /// where the banner must take no room at all — could not otherwise be measured.
    private let isAccessibilityGranted: @MainActor () -> Bool

    init(
        service: SmartDockService,
        hotkeyManager: HotkeyManager,
        prefs: UserPreferences = .shared,
        decideDraft: @escaping @MainActor (Mode) -> DraftDecision = SettingsWindow.askWithAlert,
        isAccessibilityGranted: @escaping @MainActor () -> Bool = { AccessibilityChecker.isGranted }
    ) {
        self.isAccessibilityGranted = isAccessibilityGranted
        self.service = service
        self.prefs = prefs
        self.decideDraft = decideDraft
        self.hotkeyRecorder = HotkeyRecorder(hotkeyManager: hotkeyManager, prefs: prefs)
        super.init()

        hotkeyRecorder.onFinish = { [weak self] in
            self?.updateHotkeyButtons()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .smartDockStateDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    func show(tab: Tab = .dock) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            selectTab(tab)
            return
        }

        let w = makeWindow()
        window = w
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installKeyMonitor()

        selectedMode = Mode(service.activeProfile)
        dockTab.selectedMode = selectedMode
        loadCurrentMode()
        selectTab(tab)
    }

    /// Installs a local key monitor for ⌘0 (reset window size) and Escape (close window).
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    /// The window's two keys. Returns `nil` when the event was consumed. Internal
    /// so a test can send it a synthetic event the way the monitor would.
    func handleKey(_ event: NSEvent) -> NSEvent? {
        // ⌘0 — reset window to default size
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "0" {
            window?.setContentSize(Self.defaultContentSize)
            window?.center()
            return nil
        }

        // Escape — close window (but skip while recording a hotkey; that flow owns Escape)
        if event.keyCode == 53, !hotkeyRecorder.isRecording {
            window?.performClose(nil)
            return nil
        }

        return event
    }

    // MARK: - Window Construction

    /// Tall enough that no tab scrolls at the default size. Measured: the Dock tab
    /// needs 630pt (552 before the indicator and minimize-into-app toggles, 622 when the
    /// menu bar arrived as a checkbox) and General 116, with the header and tab control
    /// above them taking another 120. The scroll view on the Dock tab stays as the safety net for
    /// a shrunk window — it is not a substitute for a size that fits.
    ///
    /// 800 since the profile picker became two tiles: a tile carries an icon above a
    /// name where a segment carried words. The Dock tab measures **660** and so needs
    /// 780; the extra 20 is deliberate. The window sat at **2pt** of spare height before
    /// this, and the very next control did not fit. The maximum below is 900, so there is
    /// room; a 13-inch laptop has about 900pt of usable height, which is why the maximum
    /// is where it is.
    ///
    /// `theDockTabFitsTheDefaultWindowWithoutScrolling` measures it rather than trusting
    /// this comment: the 600 above went stale the moment a checkbox was added, and
    /// nothing failed.
    static let defaultContentSize = NSSize(width: 420, height: 800)

    private func makeWindow() -> NSWindow {
        let (w, contentView) = UI.glassWindow(
            title: "SmartDock",
            size: Self.defaultContentSize,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView]
        )

        // Bounded resize range — user can shrink down to minimum readable size.
        w.contentMinSize = NSSize(width: 380, height: 500)
        w.contentMaxSize = NSSize(width: 600, height: 900)
        w.setContentSize(Self.defaultContentSize)

        // Don't persist resized frame across sessions — always open at default.
        w.setFrameAutosaveName("")

        buildUI(in: contentView)
        return w
    }

    // MARK: - UI Construction

    /// The window's chrome, in the order it is read: header, tabs, the four tab
    /// containers, then the layout that places them. It was one 151-line function.
    private func buildUI(in container: NSView) {
        buildHeader(in: container)
        buildTabControl(in: container)
        buildTabs(in: container)
        activateLayout(in: container)
    }

    /// Icon, name and version — the only part of the window that is not a tab.
    private func buildHeader(in container: NSView) {
        headerIconView = NSImageView()
        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        headerIconView.imageAlignment = .alignCenter
        container.addSubview(headerIconView)

        headerNameLabel = UI.label("SmartDock", font: .systemFont(ofSize: 18, weight: .semibold))
        container.addSubview(headerNameLabel)

        headerVersionLabel = UI.label(
            "v\(Bundle.main.shortVersion) \u{00B7} Made with \u{2764} by Alex Karatai",
            font: .systemFont(ofSize: 11))
        headerVersionLabel.textColor = .tertiaryLabelColor
        container.addSubview(headerVersionLabel)
    }

    private func buildTabControl(in container: NSView) {
        tabControl = NSSegmentedControl(
            labels: Tab.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(tabChanged)
        )
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        tabControl.selectedSegment = 0
        tabControl.segmentStyle = .automatic
        container.addSubview(tabControl)
    }

    /// The four tabs. Each is a model the window keeps and a SwiftUI view hosted in an
    /// `NSHostingView`; only the Dock tab gets a scroll view, as the safety net for a
    /// window shrunk below its default.
    private func buildTabs(in container: NSView) {
        buildDockTab(in: container)

        generalModel = GeneralSettingsModel(service: service, prefs: prefs)
        generalContainer = addHiddenTab(GeneralTabContent(model: generalModel), to: container)

        accessibilityStatus = AccessibilityStatusModel(
            prefs: prefs, isGranted: isAccessibilityGranted)
        shortcutsModel = ShortcutsModel(
            recorder: hotkeyRecorder, accessibility: accessibilityStatus, prefs: prefs)
        shortcutsContainer = addHiddenTab(ShortcutsTabContent(model: shortcutsModel), to: container)

        aboutModel = AboutModel(service: service, prefs: prefs)
        aboutContainer = addHiddenTab(AboutTabContent(model: aboutModel), to: container)
    }

    /// The Dock tab and the callbacks that make its intents reach this window. It owns
    /// no behaviour: every button there asks, and the draft rules answer from here.
    private func buildDockTab(in container: NSView) {
        dockTab = DockTabModel()
        dockTab.onModeChange = { [weak self] mode in self?.modeChanged(to: mode) }
        dockTab.onEdited = { [weak self] in
            guard let self else { return }
            headerIconView.image = PositionIcon.image(for: dockTab.configuration.position, selected: true)
            markDirty()
        }
        dockTab.onApply = { [weak self] in self?.saveAndApply() }
        dockTab.onDiscard = { [weak self] in self?.discardChanges() }
        dockTab.onUseCurrentDock = { [weak self] in self?.useCurrentDock() }
        dockTab.onSyncFromSystem = { [weak self] in self?.syncFromSystem() }

        settingsScroll = NSScrollView()
        settingsScroll.translatesAutoresizingMaskIntoConstraints = false
        settingsScroll.hasVerticalScroller = true
        settingsScroll.autohidesScrollers = true
        settingsScroll.drawsBackground = false

        let host = NSHostingView(rootView: DockTabContent(model: dockTab))
        host.translatesAutoresizingMaskIntoConstraints = false
        dockContainer = host
        settingsScroll.documentView = host
        container.addSubview(settingsScroll)
    }

    /// One SwiftUI tab, hosted and hidden until its segment is picked.
    private func addHiddenTab(_ content: some View, to container: NSView) -> NSView {
        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.isHidden = true
        container.addSubview(host)
        return host
    }

    private func activateLayout(in container: NSView) {
        NSLayoutConstraint.activate([
            headerIconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            headerIconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.margin),
            headerIconView.widthAnchor.constraint(equalToConstant: 36),
            headerIconView.heightAnchor.constraint(equalToConstant: 36),

            headerNameLabel.centerYAnchor.constraint(equalTo: headerIconView.centerYAnchor, constant: -8),
            headerNameLabel.leadingAnchor.constraint(equalTo: headerIconView.trailingAnchor, constant: 10),

            headerVersionLabel.topAnchor.constraint(equalTo: headerNameLabel.bottomAnchor, constant: 1),
            headerVersionLabel.leadingAnchor.constraint(equalTo: headerNameLabel.leadingAnchor),

            tabControl.topAnchor.constraint(equalTo: headerIconView.bottomAnchor, constant: 18),
            tabControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.margin),
            tabControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.margin),

            settingsScroll.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 14),
            settingsScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            settingsScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            settingsScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Width tied to the clip view so the tab never scrolls sideways; height
            // is left to the content, which is what gives the scroller something to
            // scroll when the card grows.
            dockContainer.topAnchor.constraint(equalTo: settingsScroll.contentView.topAnchor),
            dockContainer.leadingAnchor.constraint(equalTo: settingsScroll.contentView.leadingAnchor),
            dockContainer.trailingAnchor.constraint(equalTo: settingsScroll.contentView.trailingAnchor),
            dockContainer.widthAnchor.constraint(equalTo: settingsScroll.contentView.widthAnchor),
        ])

        // The other three share one shape, so they share one loop. Spelled out three
        // times before, comment and all — and a list repeated is a list that drifts.
        //
        // Pinned at the **bottom** as well as the top: a hosting view left to its own
        // `fittingSize` came up short of what SwiftUI actually drew, and the last line
        // of the tab was clipped against a frame that ended above it. With no scroll
        // view on these three, that line was simply unreachable.
        for tab in [generalContainer, shortcutsContainer, aboutContainer] {
            guard let tab else { continue }
            NSLayoutConstraint.activate([
                tab.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 14),
                tab.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                tab.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                tab.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
    }

    // MARK: - Shortcuts Tab

    /// The view that holds a tab's contents. Only the Dock tab sits in a scroll view;
    /// the other three are pinned straight into the window, so a test needs to measure
    /// them to know whether what they hold can be reached at all.
    func container(for tab: Tab) -> NSView? {
        switch tab {
        case .dock: dockContainer
        case .general: generalContainer
        case .shortcuts: shortcutsContainer
        case .about: aboutContainer
        }
    }

    // MARK: - Tab Switching

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        guard let tab = Tab(rawValue: sender.selectedSegment) else { return }
        selectTab(tab)
    }

    private func selectTab(_ tab: Tab) {
        // A draft on the Dock tab survives a tab switch untouched. It used to be
        // applied here, which turned "let me look at Shortcuts for a second" into a
        // change to the Dock the user never confirmed.

        // Cancel hotkey recording if leaving Shortcuts
        if currentTab == .shortcuts && tab != .shortcuts && hotkeyRecorder.isRecording {
            // Through the model, so the row stops saying it is listening too.
            shortcutsModel.stopRecording()
        }

        currentTab = tab
        tabControl.selectedSegment = tab.rawValue

        settingsScroll.isHidden = tab != .dock
        generalContainer.isHidden = tab != .general
        shortcutsContainer.isHidden = tab != .shortcuts
        aboutContainer.isHidden = tab != .about
    }

    // MARK: - Actions

    private func modeChanged(to target: Mode) {
        guard target != selectedMode else { return }

        // The form is about to show a different profile, so a draft here really
        // would be lost — this is the one place a question is warranted.
        if isDirty {
            switch askAboutDraft() {
            case .apply: saveAndApply()
            case .discard: break
            case .cancel:
                dockTab.selectedMode = selectedMode
                return
            }
        }
        selectedMode = target
        // The segment has to be moved here. An `NSSegmentedControl` moved itself on the
        // click and the host only put it *back* when it refused; a SwiftUI `Picker` bound
        // through `requestMode` moves for nobody until this line runs, so without it the
        // form showed one profile while the picker claimed the other.
        dockTab.selectedMode = target
        loadCurrentMode()
        markClean()
    }

    enum DraftDecision { case apply, discard, cancel }

    /// Apply / Discard / Cancel for a draft that is about to be lost. Only two paths
    /// reach it — switching profiles and closing the window. Everything else keeps
    /// the draft where it is.
    private func askAboutDraft() -> DraftDecision { decideDraft(selectedMode) }

    /// The app's answer to `askAboutDraft`: a modal alert.
    static func askWithAlert(for mode: Mode) -> DraftDecision {
        let alert = NSAlert()
        alert.messageText = "Apply changes to the \(mode.title) profile?"
        alert.informativeText = "The Dock settings you changed have not been applied."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .apply
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    /// Seeds the form from the live Dock, leaving the Dock itself untouched.
    ///
    /// Reads through the controller rather than the service's `currentConfig`: that
    /// one is what SmartDock last *asked* for, and the point here is what the Dock
    /// actually holds — the two differ whenever macOS refused a setting.
    private func useCurrentDock() {
        populate(from: service.dockController.readSystemConfig())
        markDirty()
        Log.info("Settings: seeded the form from the live Dock")
    }
    private func syncFromSystem() {
        prefs[selectedMode.profile] = service.dockController.readSystemConfig()
        loadCurrentMode()
        markClean()
    }

    /// Display state changed — refresh Settings UI.
    /// A display change or a verified apply while the window is open. Refreshes what
    /// describes the outside world — status, active-profile marker, refusal — and
    /// leaves the form alone if it holds a draft. It used to apply the draft first, on
    /// the reasoning that reloading would lose it; plugging in a monitor mid-edit
    /// therefore committed whatever the sliders happened to be at.
    @objc private func handleStateChange(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        updateStatus()
        updateModeTitles()
        updateRefusalNotice()
        if !isDirty { loadCurrentMode() }
    }

    // MARK: - Dirty State

    private var isDirty: Bool { dockTab.isDirty }
    private func markDirty() { dockTab.isDirty = true }
    private func markClean() { dockTab.isDirty = false }

    private func discardChanges() {
        loadCurrentMode()
        markClean()
    }

    // MARK: - Load / Save

    private func loadCurrentMode() {
        populate(from: activeConfig)
        updateStatus()
        updateModeTitles()
        updateRefusalNotice()
    }

    /// Fills every control from a configuration.
    ///
    /// Shared by loading a stored profile and by **Use Current Dock**, so the two
    /// cannot drift: a control added to the form but forgotten in one of them would
    /// show a stale value from the other.
    private func populate(from config: DockConfiguration) {
        dockTab.configuration = config
        headerIconView.image = PositionIcon.image(for: config.position, selected: true)
    }

    private func saveAndApply() {
        prefs[selectedMode.profile] = dockTab.configuration

        markClean()
        // Re-applying the profile by name keeps an on-request override in force;
        // `refresh()` would re-derive it from the displays and silently drop it.
        if selectedMode.profile == service.activeProfile { service.applyProfile(selectedMode.profile) }
        updateStatus()
    }

    /// Stored config for the mode currently shown in the Settings tab.
    private var activeConfig: DockConfiguration { prefs[selectedMode.profile] }

    // MARK: - Helpers

    private func updateStatus() { dockTab.status = statusText() }

    private func statusText() -> String { "Current: \(service.activeProfileDescription)" }

    private func updateModeTitles() { dockTab.markActive(Mode(service.activeProfile)) }

    private func updateRefusalNotice() {
        dockTab.refusalNotice = service.dockController.lastApplyOutcome?.refusalNotice
    }

    /// The recorder finished on its own, having stored or cleared a binding — the
    /// rows re-read their titles from `UserPreferences`, which is not observable.
    private func updateHotkeyButtons() {
        shortcutsModel?.recordingFinished()
    }
}

// MARK: - NSWindowDelegate

extension SettingsWindow: NSWindowDelegate {
    /// Back from System Settings, where the person may have just switched SmartDock on.
    /// The permission was read once per window before this, so the Shortcuts tab went on
    /// saying *Not allowed* over a permission that had been granted a moment earlier —
    /// measured, and only closing the window cleared it.
    public func windowDidBecomeKey(_ notification: Notification) {
        accessibilityStatus?.refresh()
    }

    /// Closing used to drop a draft without a word, while every other exit applied
    /// it — inconsistent in both directions. Now it asks, and Cancel keeps the window.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isDirty else { return true }
        switch askAboutDraft() {
        case .apply:
            saveAndApply()
            return true
        case .discard: return true
        case .cancel: return false
        }
    }

    public func windowWillClose(_ notification: Notification) {
        if hotkeyRecorder.isRecording { shortcutsModel?.stopRecording() }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        window = nil
    }
}

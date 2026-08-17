# CLAUDE.md

Project instructions for Claude Code. Follow these exactly.

## Build & Run

```bash
make build          # swift build -c release
make test           # swift test (sequential — parallel is flaky due to shared UserPreferences singleton)
make app            # build + icon + .app bundle (ad-hoc signed)
make run            # build + bundle + open
make clean          # remove build artifacts
```

Code quality:
```bash
make format         # rewrite sources with swift-format (rules in .swift-format)
make lint           # check formatting without writing — CI gates on this
make coverage       # run tests and print a per-file llvm-cov table
```

Single test:
```bash
swift test --filter SmartDockTests.SmartDockServiceTests/testStartBeginsMonitoring
```

## Version & Release

```bash
make bump V=1.2.3   # update the version everywhere + increment build number
make version-check  # verify all version references agree (bump runs this itself)
make release        # build + zip + gh release create (working tree must be clean)
make install        # copy .app to /Applications
make fix            # xattr -cr + codesign (fix Gatekeeper quarantine)
```

**Never edit a version by hand — always `make bump`.** The version is written in four places, and `bump` is the only thing that knows all of them:

| Where | What |
|---|---|
| `Makefile` | `VERSION := x.y.z` in the `# === Config ===` block — **source of truth** |
| `Resources/Info.plist` | `CFBundleShortVersionString` |
| `Resources/Info.plist` | `CFBundleVersion` — build number, incremented by 1 (never set from `V`) |
| `README.md` | shields.io badge — both the URL and its `alt` text |
| `CHANGELOG.md` | a dated `## [x.y.z]` section, opened directly under `## [Unreleased]` |

`bump` finishes by running `version-check`, which fails if any reference is stale. `release.yml` calls `make bump` rather than re-implementing it — if you add a fifth place, add it to the `bump` target and to `version-check`, and CI picks it up for free.

**Do not delete the `## [Unreleased]` heading from `CHANGELOG.md`.** It is not decoration:
`bump` inserts the new version's section immediately below it, so removing the line makes
bump silently stop recording releases. Entries accumulate under `[Unreleased]` as work
lands, and `bump` converts them into the dated section. The section was forgotten by hand
on three consecutive releases, which is why `version-check` now gates on it too.

Examples in docs use `V=1.2.3` on purpose: a placeholder that never collides with a real version, so grepping the current version only finds actual definitions.

Diagnostics:
```bash
make doctor         # verify dev environment (swift, xcode, codesign, gh, git)
make outdated       # print Swift/Xcode/Actions versions in use
make actions-check  # compare GitHub Actions versions against latest (requires gh)
make logs           # stream live SmartDock logs (subsystem com.smartdock.app)
```

## CI/CD

Two GitHub Actions workflows in `.github/workflows/`:

**`ci.yml`** — runs on push to `main`/`dev` and PRs to `main`:
- Concurrency group per branch — cancels in-progress runs on new push
- SPM cache (`actions/cache` on `.build` dir)
- `make version-check` → `make lint` → `make coverage` → `swift build -c release`
- `make lint` runs **before** the build so a formatting-only PR fails in seconds
- `make coverage` replaces a bare `swift test`: same suite, plus instrumentation, so the
  tests are not compiled and run twice. Its table is written to `$GITHUB_STEP_SUMMARY`
- The coverage step sets `shell: bash` deliberately — the default runner shell is
  `bash -e` **without** `pipefail`, so `make coverage | tee` would mask a failing test
  run behind `tee`'s exit code
- `make app` + `codesign --verify --strict` — exercises icon generation, entitlements and ad-hoc signing, which `swift build` never touches. Without this step those only run at release time, so a break would surface mid-release instead of on the PR. The `codesign --display --entitlements` output also asserts all three entitlements actually made it into the bundle.

**`dependabot.yml`** — monthly grouped PR for GitHub Actions bumps. Only the `github-actions` ecosystem is configured: the package has no external SPM dependencies, so a `swift` entry would do nothing.

**`release.yml`** — runs on `v*` tag push. Four jobs in a pipeline:
```
🧪 Test  →  🔨 Build  →  🎉 Release  →  🍺 Homebrew
```
- **Test**: runs `swift test`
- **Build**: bumps version in Makefile/Info.plist, runs `make app`, uploads zip as artifact
- **Release**: downloads artifact, creates GitHub Release with `gh release create`
- **Homebrew**: computes sha256, updates Cask + Formula in `alexeikaratai/homebrew-tap`

Both workflows set the Xcode version via `env.XCODE_PATH` at workflow level — one place per file, never inline in a step. The runner (`runs-on:`) and `XCODE_PATH` must agree: check the [runner image readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) for which Xcode versions are actually installed before bumping either.

Action versions are pinned by major (`@v7`). Run `make actions-check` to see how they compare to latest — don't hardcode them into this file, it goes stale.

## Architecture

Swift Package (swift-tools-version 6.2), two targets: **SmartDockCore** (testable logic) and **SmartDock** (AppKit UI). Platform: macOS 14+, Swift 6 strict concurrency.

### Core layer (`Sources/SmartDockCore/`)

| File | Responsibility |
|---|---|
| `DockConfiguration.swift` | `DockConfiguration` value type (position, autohide, icon size as 0.0–1.0 scale, magnification). `HotkeyBinding` value type (keyCode + modifiers + displayName). `UserPreferences` persists per-mode configs via UserDefaults with migration from old pixel format. Also stores: `notificationsEnabled`, `syncFromSystemEnabled`, `hasSeenOnboarding`, `hasPromptedAccessibility`, `pendingAccessibilityGrant`, hotkey bindings. `DockPosition` enum. First-launch: `initializeDefaultsIfNeeded(from:)` reads system config, sets external=autohide off, builtin=autohide on. |
| `DisplayMonitor.swift` | Detects external monitor connect/disconnect via `CGDisplayRegisterReconfigurationCallback`. Debounces (1s settle delay). Filters by add/remove/enable/disable CG flags only, via the testable free function `shouldReactToDisplayChange(_:)`. Also observes `didWakeNotification`, `screensDidWakeNotification` (2s delay re-check). No space change observer — AppleScript triggers space notifications causing feedback loops. Conforms to `DisplayMonitoring`. |
| `DockController.swift` | Applies `DockConfiguration` via `NSAppleScript` → System Events. Diff-based: reads current system config via fresh `UserDefaults(suiteName: "com.apple.dock")` and only applies properties that actually differ. Observes external dock preference changes via KVO on `UserDefaults(suiteName: "com.apple.dock")` using private `DockPrefsObserver` helper (NSObject for KVO). Debounces 0.5s, compares with `lastAppliedConfig` to filter own changes. Conforms to `DockControlling`. |
| `SmartDockService.swift` | Orchestrator: reads `UserPreferences`, applies appropriate config based on display state. Handles external dock changes (System Settings sync): updates active profile when system config diverges from `lastAppliedConfig`. Has `SmartDockServiceDelegate`. Posts `Notification.Name.smartDockStateDidChange` only when state actually changes. |
| `URLCommand.swift` | Parses `smartdock://` URLs into commands. Pure — lives in Core so it is covered by the test target. Rejects foreign schemes, unknown verbs and ambiguous input (`smartdock://switch` with no target) rather than guessing. |
| `AppleScriptCommand.swift` | `DockProfile` — the `dock profile` enumeration from `SmartDock.sdef`, mapping four-character Apple Event codes to `URLCommand`. In Core so the codes are testable; `AppleScriptCommandTests` pins them to literals **and** greps the shipped `.sdef` to catch drift between the two hand-written copies. |
| `DockApplyOutcome.swift` | What an apply actually achieved, established by reading the Dock back — `NSAppleScript` reports success as soon as the script runs, so a silently-refused setting is otherwise invisible. Only properties that were **requested** can be reported rejected; anything else that differs was changed by something outside the app. |
| `RateLimiter.swift` | `RateLimiter` (hotkey rate limiting) and `ProfileSwitchAnnouncer` (notification cooldown + duplicate suppression). Both take `now` as an argument so interval edges are testable without sleeping. The announcer records a state **only when a banner actually shows** — recording a suppressed one would swallow the next genuine switch back to it. |
| `PendingCommandQueue.swift` | Holds `smartdock://` / Apple Event commands that arrive before `applicationDidFinishLaunching` builds the managers. In Core because leaving it in `AppDelegate` put the fix for a launch-time crash in the one target with no tests. |
| `DiagnosticReport.swift` | Value type + Markdown formatting for the About tab's **Copy Diagnostic Info**. Holds versions, permission flags, display counts and dock profiles — never anything identifying, since the output is pasted into public issues. |
| `Log.swift` | Centralized `Logger` API. Subsystem `com.smartdock.app`. Categories: `general`, `display`. |

### App layer (`Sources/SmartDock/`)

| File | Responsibility |
|---|---|
| `ScriptingSupport.swift` | `NSScriptCommand` subclasses backing `SmartDock.sdef`. Each is `@objc(SD…Command)` because the dictionary binds by Objective-C runtime name. `performDefaultImplementation` is inherited `nonisolated`, so it reaches `@MainActor` state via `MainActor.assumeIsolated` — sound because Apple Events are delivered on the main thread, and hopping off it would lose event ordering. Bad input sets `scriptErrorNumber`/`scriptErrorString` rather than guessing a profile. |
| `App.swift` | `@main` AppDelegate with manual `NSApplication` run loop (no storyboards). Prompts Accessibility on first launch only (avoids re-prompting after Homebrew updates). Creates `NotificationManager`, `HotkeyManager`, `AppUpdateWatcher`, shows `OnboardingWindow` on first launch. After "Reset Permission" relaunch: opens Shortcuts tab + System Settings, polls `AXIsProcessTrusted` (1s, max 5min), auto-relaunches when granted. `applicationShouldHandleReopen` opens Settings when re-launched from /Applications. |
| `StatusBarController.swift` | Menu bar icon (`dock.rectangle` SF Symbol) + dropdown menu with SF Symbol icons per item. Implements `NSMenuDelegate`, `SmartDockServiceDelegate`. Exposes `showSettings()` for re-open handling. Passes `HotkeyManager` to `SettingsWindow`. Menu items: Settings, Shortcuts, About open SettingsWindow on the corresponding tab. |
| `SettingsWindow.swift` | Tabbed glass NSWindow (`NSVisualEffectView`) with 3 tabs: **Settings** (dock config card with mode control + general + buttons), **Shortcuts** (5 hotkey rows), **About** (version, links). Tab switching auto-saves dirty Settings and cancels hotkey recording. Apply button centered in card. Resizable (380×500 to 600×900) with ⌘0 to reset to default 420×660. Observes `smartDockStateDidChange` to refresh UI. Delegates self-contained pieces to `Views/` and `HotkeyRecorder`. |
| `HotkeyRecorder.swift` | Captures a keystroke and stores it as a `HotkeyBinding`. Pauses `HotkeyManager` while recording so the key being bound doesn't fire its own action. Escape clears the binding; a Cmd/Ctrl/Opt modifier is required. `onFinish` tells the host to refresh its buttons. |
| `NotificationManager.swift` | Posts macOS banner notifications (`UNUserNotificationCenter`) on profile switch. Observes `.smartDockStateDidChange`. Cooldown 3s. Lazy authorization request. `UNUserNotificationCenterDelegate` for foreground banners. |
| `HotkeyManager.swift` | Global keyboard shortcuts via `NSEvent.addGlobalMonitorForEvents` + `addLocalMonitorForEvents`. `HotkeyAction` enum: `.toggleAutohide`, `.refreshNow`, `.switchToExternal`, `.switchToBuiltin`, `.openSettings`. Cached bindings, rate limiting 0.3s, `isRecording` flag pauses dispatch during recording. |
| `OnboardingWindow.swift` | Welcome screen shown once on first launch. Glass window with app description, feature list, "Get Started" button. Sets `hasSeenOnboarding` on close. |
| `AppRelauncher.swift` | Spawns shell that waits for current PID to exit (max 5s), then opens new instance via `open -n`. Bundle path passed via env var (no shell injection). Used by Reset Permission and update prompt. |
| `AppUpdateWatcher.swift` | Watches `Bundle.main.executablePath` via `DispatchSource.makeFileSystemObjectSource` for delete/write/rename events. On Homebrew upgrade: debounce 2s, prompt user "SmartDock was updated. Relaunch?". Uses `AppRelauncher` for safe relaunch. |
| `LaunchAtLogin.swift` | `SMAppService.mainApp` wrapper. |
| `AccessibilityChecker.swift` | `AXIsProcessTrusted()` check. Prompts system dialog only on first launch (`hasPromptedAccessibility` flag). Accessibility needed only for global hotkeys — core dock switching works without it. |

### View layer (`Sources/SmartDock/Views/`)

Self-contained UI pieces extracted out of `SettingsWindow`. Each owns its own layout and actions; the host only wires callbacks.

| File | Responsibility |
|---|---|
| `UI.swift` | Static factories shared by all windows: `label`, `smallButton`, `checkbox`, `scaleSlider`, `glassCard`, `glassWindow`. `glassWindow` returns the window plus the content view to build into — the window's own `contentView` is the `NSVisualEffectView` behind it. |
| `PositionIcon.swift` | Draws the monitor thumbnails for the position picker and Settings header. Pure drawing, so each (position, selected) pair is rendered once and cached. |
| `PositionPicker.swift` | `NSStackView` subclass — one icon+label button per `DockPosition`. Owns its highlighting; `selectedPosition` repaints via `didSet`, `onSelectionChange` fires only on user taps (not on programmatic loads). |
| `AboutTabView.swift` | `NSView` subclass with the About tab contents: icon, version, description, GitHub/Changelog links. |
| `AccessibilityWarningView.swift` | `NSView` subclass — yellow banner shown on the Shortcuts tab while Accessibility is missing. Owns "Open System Settings" and the `tccutil reset` + relaunch flow. Hidden when `AccessibilityChecker.isGranted`. |

### Tests (`Tests/SmartDockTests/`)

- `Mocks.swift` — `MockDisplayMonitor`, `MockDockController`, `MockServiceDelegate`
- `AppleScriptCommandTests.swift` — Apple Event code stability, decoding, `.sdef` parity
- `DockApplyOutcomeTests.swift` — silent refusal detection, tolerance, blame scoping
- `RateLimiterTests.swift` — interval edges, and that blocked attempts don't push the deadline out
- `PendingCommandQueueTests.swift` — launch-time queueing, ordering, drain-once
- Protocol-based DI: inject mocks via `DisplayMonitoring` / `DockControlling` protocols
- All tests are `@MainActor`-compatible

## Swift Code Style

### Naming
- **Types**: `UpperCamelCase` — `DockConfiguration`, `DisplayMonitor`, `SmartDockService`
- **Functions, properties, variables**: `lowerCamelCase` — `externalDisplayCount()`, `hasExternalDisplay`, `lastExternalCount`
- **Constants**: `lowerCamelCase` (not `SCREAMING_SNAKE`) — `let settleDelay: TimeInterval = 1.0`
- **Protocols**: noun or adjective, suffix `-ing` / `-able` / `-ible` for capabilities — `DisplayMonitoring`, `DockControlling`, `Sendable`
- **Enums**: type `UpperCamelCase`, cases `lowerCamelCase` — `case bottom`, `case left`
- **Bool naming**: read as assertions — `isEnabled`, `isRunning`, `hasExternalDisplay` (not `enabled`, `external`)
- **Abbreviations**: treat as words — `iconId` not `iconID`, `urlString` not `URLString`. Exception: two-letter (`ID`, `UI`) stay uppercased when alone.

### Code Organization
- Use `// MARK: -` sections in every file: `Protocol`, `Implementation`, `Public`, `Private`, `Actions`, `Helpers`
- One type per file. Small related types (e.g. `DockPosition` enum in `DockConfiguration.swift`) are okay in the same file.
- Order within a type: properties → init → public methods → private methods
- Group related constraints/setup in dedicated `private func` — e.g. `buildUI(in:)`, `setupStatusItem()`
- Extensions for protocol conformance go at the bottom of the file with their own `// MARK: -`

### Access Control
- Default to most restrictive: `private` for implementation details, `fileprivate` only when needed by extensions in the same file
- `public` only on API that SmartDock target consumes from SmartDockCore
- `internal` (default) is fine within a single target — don't write it explicitly
- `final` on all classes — this project has no inheritance (except `NSObject` for AppKit interop)

### Types & Data
- Prefer `struct` over `class`. Use `class` only when: reference semantics needed, `NSObject` subclass required, or actor isolation requires it.
- Prefer `let` over `var`. Use `var` only when mutation is required.
- Use `enum` with no cases for namespaces (e.g. `Log`, `AccessibilityChecker` if static-only)
- No force unwraps (`!`) except `IBOutlet`-style patterns with `NSStatusItem` / `NSMenuItem` where the object is set immediately after init
- No `Any` / `AnyObject` unless interfacing with Objective-C APIs
- Use `guard` for early returns, `if let` for optional binding in the middle of flow

### Functions & Closures
- Prefer trailing closure syntax for the last closure parameter
- Use `[weak self]` in escaping closures. Use `guard let self else { return }` pattern inside.
- Prefer `@discardableResult` over ignoring return values with `_ =`
- Keep functions short — if a function is over ~40 lines, extract helpers
- Use default parameter values instead of overloads — `init(autohide: Bool = false, ...)`

### Error Handling
- Prefer `Bool` return for simple success/fail (e.g. `runAppleScript`) — no need for `throws` on fire-and-forget operations
- Use `guard` + early return over nested `if let`
- Log errors via `Log.error()` at the point of failure, don't propagate error messages up

### Formatting

**`swift-format` is authoritative — do not hand-format.** Rules live in `.swift-format`
at the repo root; `make format` applies them and `make lint` fails CI on any deviation.
The tool ships inside the Xcode toolchain, so this adds no external dependency. Reach it
via `xcrun swift-format` — a bare `swift-format` is not on `PATH`.

What the config enforces: 4-space indentation, 120-column lines, no semicolons, trailing
commas in multi-line collections, sorted imports, at most one consecutive blank line.

Do **not** align code into columns by hand — the formatter strips it, and realigning a
block on every rename is exactly the diff noise the tool exists to remove:
```swift
case refresh          = "refresh"   // ✗ formatter collapses this
case refresh = "refresh"            // ✓
```

Several rules are disabled on purpose (implicitly unwrapped optionals in `AppDelegate`,
force-unwraps in AppKit setup, `public extension`, the hand-written `DockConfiguration`
init). Each exclusion and its reason is tabulated in `CONTRIBUTING.md` — if you find
yourself wanting to re-enable one, read that first.

Still a judgement call, since no rule covers it: use string interpolation `"\(value)"`
rather than concatenation, except in long multi-part log messages where `+` reads better.

### Swift Patterns Used in This Project
- **Protocol + concrete class** — define protocol first (`DockControlling`), then implementation (`DockController`). All external dependencies consumed via protocol.
- **Delegate pattern** — `SmartDockServiceDelegate` with `weak var delegate`. Delegate methods prefixed with subject: `serviceDidUpdateState(_:hasExternal:)`.
- **Value types for configuration** — `DockConfiguration` is a `struct`, immutable after init. Create new instance to change values.
- **Singleton via static let** — `UserPreferences.shared` with `private init()`. Only for app-wide state, never for testable services.
- **Extensions for helpers** — `private extension Int { func clamped(to:) }`, `extension Bundle { var shortVersion }` (internal, shared across SmartDock target). Keep helpers close to usage, private when single-file.
- **`lazy var`** for expensive one-time setup — `lazy var settingsWindow`, `lazy var cachedIcon`

## Swift & macOS Conventions

### Swift 6 Strict Concurrency
- **All** core and UI types must be `@MainActor`-isolated. This is a hard requirement, not a suggestion.
- Value types (`DockConfiguration`, `DockPosition`) must be `Sendable`.
- Use `nonisolated(unsafe)` only for flags accessed from both `deinit` (nonisolated) and `@MainActor` methods — document why.
- Never use `Task.detached` or `nonisolated` to escape actor isolation without a clear reason.
- Closures passed across isolation boundaries must be `@Sendable`. Watch for implicit captures.

### AppKit Patterns
- **No storyboards/nibs.** All UI is programmatic with Auto Layout (`translatesAutoresizingMaskIntoConstraints = false`).
- Menu bar app: `LSUIElement = true` in Info.plist. No Dock icon. Do NOT call `NSApp.setActivationPolicy(.accessory)` — it's redundant with LSUIElement and can cause status items to disappear during launch.
- Glass/vibrancy: `NSVisualEffectView` with `.hudWindow` (window) or `.popover` (cards) material.
- Use `NSLayoutConstraint.activate([...])` for batch constraint activation — never `constraint.isActive = true` one by one.
- Size sliders are `isContinuous = true` and only mark dirty state on drag — they do **not** display a numeric value. The label beside each slider is a static "Small ◀─▶ Large" hint (`makeScaleHintLabel()`). Changes apply only when the user clicks Apply — no auto-save on mouseUp.
- SF Symbols: always provide programmatic fallback for icons. Set `isTemplate = true` for menu bar icons.

### AppleScript / System Events
- Each Dock property (`autohide`, `position`, `dock size`, `magnification`, `magnification size`) is set in its **own** `tell application "System Events" / tell dock preferences` block. Never combine them — if one fails, others still apply.
- No `killall Dock`. AppleScript via System Events updates the Dock gracefully.
- Sizes use 0.0–1.0 scale internally (same as macOS System Events). Convert via `DockConfiguration.pixelsToScale()` / `scaleToPixels()`. Diff-based apply uses 0.01 tolerance to avoid rounding noise.

### CoreGraphics Display Callbacks
- Use `CGDisplayRegisterReconfigurationCallback` — event-driven, no polling/timers.
- Filter the C callback through `shouldReactToDisplayChange(_:)` — an internal free function in `DisplayMonitor.swift`, extracted so the filtering rules are unit-testable without a real display.
- Only react to **add/remove/enable/disable** (`.addFlag`, `.removeFlag`, `.enabledFlag`, `.disabledFlag`). Ignore mode changes, moves, mirroring and desktop shape changes — these fire during Mission Control and fullscreen transitions.
- Ignore `.beginConfigurationFlag` — react only to completion. It is skipped even when bundled with topology flags, since the completion callback follows.
- Use the named `CGDisplayChangeSummaryFlags` constants, never raw hex.
- Debounce with 1-second settle delay before checking display count. CG fires multiple callbacks during transitions.
- Track `lastExternalCount` — only fire `onConfigurationChanged` when the external display count **actually** changes.
- `CGDisplayIsBuiltin()` distinguishes built-in from external displays.
- `externalDisplayCount()` additionally filters by `CGDisplayIsActive` + `!CGDisplayIsAsleep` — skips sleeping monitors, clamshell mode, phantom USB-C hub connections.

### Wake & Space Change Observers
- `NSWorkspace.didWakeNotification` + `screensDidWakeNotification` — after macOS sleep/wake, force re-check with 2-second delay (longer than CG debounce). Uses separate `pendingWakeCheck` work item so CG callbacks can't cancel it. Always re-applies config regardless of count change.
- `NSWorkspace.activeSpaceDidChangeNotification` — **NOT observed**. AppleScript dock changes (especially autohide) trigger space change notifications, causing infinite feedback loops. Mission Control and fullscreen dock behavior is left to macOS. If dock gets stuck, user can use "Refresh Now" from the menu bar.

### Diff-Based Dock Application
- `DockController.apply()` reads current system config via fresh `UserDefaults(suiteName: "com.apple.dock")` before applying.
- Only runs AppleScript for properties that actually differ from system state.
- If nothing changed → no AppleScript runs → no dock flash/appearance.
- This makes frequent re-apply calls (wake, space change) safe — they're no-ops when config matches.
- After apply, `lastAppliedConfig` is updated for system sync loop prevention.

### System Dock Sync (KVO)
- `DockPrefsObserver` (private NSObject helper in `DockController.swift`) observes 5 keys on `UserDefaults(suiteName: "com.apple.dock")` via KVO: `autohide`, `orientation`, `tilesize`, `magnification`, `largesize`.
- When any process (System Settings, `defaults write`) changes dock preferences, `cfprefsd` delivers KVO callbacks.
- Debounce 0.5s — System Settings may change multiple keys at once; batch into single check.
- Loop prevention: compare `readSystemConfig()` with `lastAppliedConfig` using `approximatelyEquals()` (0.01 tolerance for sizes). If matches → our own change → skip. If differs → external change → callback.
- `SmartDockService.handleExternalDockChange()` updates the active profile (`externalConfig` or `builtinConfig`) and notifies UI.
- Gated by `prefs.syncFromSystemEnabled` (default: true).

### Notifications
- `NotificationManager` posts macOS banners via `UNUserNotificationCenter` on profile switch.
- Observes `.smartDockStateDidChange` (same pattern as `SettingsWindow`).
- Cooldown: minimum 3s between notifications to prevent spam on rapid connect/disconnect.
- Authorization requested lazily on first notification attempt. If denied, `notificationsEnabled` is set to false.
- `UNUserNotificationCenterDelegate.willPresent` returns `[.banner, .sound]` — required for LSUIElement apps to show banners.
- No entitlements needed for non-sandboxed apps.

### Global Hotkeys
- `HotkeyManager` uses `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` (background) + `addLocalMonitorForEvents` (foreground).
- Requires Accessibility permission (already checked by `AccessibilityChecker`).
- `isRecording` flag pauses dispatch during hotkey recording in Settings.
- Bindings stored in `UserPreferences` as `HotkeyBinding` (keyCode + modifiers + displayName).
- Display names captured via `event.charactersIgnoringModifiers` — works with any keyboard layout.
- **Recording and matching must go through `HotkeyBinding` in Core**, never raw flags:
  `HotkeyBinding.normalize(_:)` when storing, `binding.matches(keyCode:modifiers:)` when
  dispatching, `binding.displayString` when showing. The mask lives in one place because
  CapsLock/Fn ride along on ordinary key events — a binding recorded under one flag state
  would silently stop firing under another. `HotkeyBindingTests` guards this.

### External Commands (URL scheme + AppleScript)

All three input paths — global hotkeys, `smartdock://` URLs and AppleScript — converge
on `AppDelegate.performCommand(_:)` → `HotkeyAction(command)` → `HotkeyManager.perform(_:)`.
One execution path, no duplicated behaviour. Keep it that way when adding a command.

- `performCommand` **queues** into `pendingCommands` when `hotkeyManager` is still nil.
  Both a URL and an Apple Event can *launch* the app, and that event can arrive before
  `applicationDidFinishLaunching` has built the managers — unwrapping there would crash.
  `drainPendingCommands()` runs at the end of launch.
- The `HotkeyAction(URLCommand)` switch is exhaustive on purpose: adding a case to
  either enum breaks the build until both agree.

**URL scheme** — `smartdock://` registered via `CFBundleURLTypes`; `URLCommand` (Core)
parses. Parsing rejects rather than guesses: unknown verbs, foreign schemes and
`smartdock://switch` with no target all return `nil`.

**AppleScript** — `NSAppleScriptEnabled` + `OSAScriptingDefinition` in `Info.plist`,
dictionary at `Resources/SmartDock.sdef`, commands in `ScriptingSupport.swift`.

- `make app` copies the `.sdef` into `Contents/Resources`. The filename must match
  `OSAScriptingDefinition` exactly — the path is resolved relative to that directory.
- Adding a command means touching **three** files: the `.sdef`, an `NSScriptCommand`
  subclass, and `URLCommand`. Nothing forces them to agree at build time, which is why
  `AppleScriptCommandTests` checks command/class counts and enumerator codes against the
  shipped dictionary.
- **Four-character codes are public API.** Scripts bind by code, not by name, so changing
  one silently breaks every script already written against it. Treat them as frozen.
- `show settings`, not `open settings` — `open` collides with the Standard Suite.

### UserDefaults
- App preferences: `UserDefaults.standard` with `com.smartdock.` prefix.
- Reading system Dock config: create fresh `UserDefaults(suiteName: "com.apple.dock")` each time — do not cache the instance, as AppleScript changes are made by the Dock process and cached instances may return stale data.
- Use `defaults.object(forKey:) != nil` to check if a key exists (`.bool(forKey:)` returns `false` for missing keys).
- First launch: `UserPreferences.initializeDefaultsIfNeeded(from:)` reads current system config, saves external mode (autohide=off) and builtin mode (autohide=on). Only runs once (`isConfigured` check).

### Testing
- Always use protocol-based dependency injection — never instantiate `DisplayMonitor` or `DockController` directly in tests.
- Mock classes live in `Tests/SmartDockTests/Mocks.swift`.
- `MockDisplayMonitor.simulateDisplayChange(externalCount:)` triggers the callback chain.
- Tests use `swift test` (sequential) — `UserPreferences.shared` singleton causes flaky failures with `--parallel`.
- `setUp` resets all `com.smartdock.*` UserDefaults keys and sets explicit defaults (`externalConfig`, `builtinConfig`, `syncFromSystemEnabled`).
- Pure logic that the system would otherwise hide (CG flag filtering, `approximatelyEquals`) is extracted into free functions/methods and tested directly — prefer that over leaving it untested inside a C callback.
- Don't assert on floating-point knife edges. `approximatelyEquals` uses a 0.01 tolerance, but `abs(0.30 - 0.31) == 0.010000000000000009` — anchor size assertions to `pixelsToScale()` values instead, which is what the tolerance actually exists for.

### Logging
- Use `Log.info()`, `Log.error()`, `Log.displayChange()` — never `print()`. Categories: `general`, `display`.
- All log output goes through `Logger` API (visible in Console.app, filter by `com.smartdock.app`).

## Entitlements & Permissions

- `com.apple.security.automation.apple-events` — required for NSAppleScript -> System Events
- `com.apple.security.scripting-targets` scoped to `com.apple.systemevents.dock.preferences`
- Sandbox: **off** (`com.apple.security.app-sandbox = false`)
- `LSUIElement = true` in Info.plist (no Dock icon)
- Accessibility: `AXIsProcessTrusted()` — prompt only on first launch (`hasPromptedAccessibility` flag). Ad-hoc signing resets macOS Accessibility permission on each rebuild/Homebrew update, so re-prompting would annoy users. Accessibility is needed only for global hotkeys — core dock switching (AppleScript) works without it.

## File Structure

```
Sources/
├── SmartDockCore/
│   ├── DockConfiguration.swift   # DockConfiguration + HotkeyBinding + UserPreferences + DockPosition
│   ├── DisplayMonitor.swift      # CG callback + debounce + flag filtering
│   ├── DockController.swift      # AppleScript Dock control + DockPrefsObserver (KVO sync)
│   ├── SmartDockService.swift    # Orchestrator: display state -> dock config + external sync
│   ├── URLCommand.swift          # smartdock:// URL parsing
│   ├── AppleScriptCommand.swift  # DockProfile ↔ Apple Event four-char codes
│   ├── DockApplyOutcome.swift    # Did the Dock actually take it? (read-back check)
│   ├── RateLimiter.swift         # Hotkey rate limit + notification announcer
│   ├── PendingCommandQueue.swift # Commands arriving before launch finishes
│   ├── DiagnosticReport.swift    # Bug-report snapshot + Markdown formatting
│   └── Log.swift                 # Logger wrapper
└── SmartDock/
    ├── App.swift                 # @main, manual NSApplication run loop
    ├── ScriptingSupport.swift    # NSScriptCommand subclasses bound by the sdef
    ├── StatusBarController.swift # Menu bar icon + dropdown with SF Symbol icons
    ├── SettingsWindow.swift      # Tabbed glass window (Settings / Shortcuts / About)
    ├── OnboardingWindow.swift    # First-launch welcome screen
    ├── NotificationManager.swift # macOS banner notifications on profile switch
    ├── HotkeyManager.swift       # Global keyboard shortcuts (5 actions)
    ├── HotkeyRecorder.swift      # Captures a keystroke and stores it as a binding
    ├── AppRelauncher.swift       # Safe relaunch — waits for PID exit before spawning new instance
    ├── AppUpdateWatcher.swift    # FS watcher on executable — detects Homebrew upgrade, prompts relaunch
    ├── LaunchAtLogin.swift       # SMAppService wrapper
    ├── AccessibilityChecker.swift # First-launch-only Accessibility prompt
    └── Views/
        ├── UI.swift                        # Shared control + glass window factories
        ├── PositionIcon.swift              # Cached monitor thumbnails per dock position
        ├── PositionPicker.swift            # NSStackView of position buttons
        ├── AboutTabView.swift              # About tab contents
        └── AccessibilityWarningView.swift  # Permission banner + tccutil reset flow
Tests/SmartDockTests/
    ├── Mocks.swift               # MockDisplayMonitor, MockDockController, MockServiceDelegate
    ├── SmartDockServiceTests.swift
    ├── DisplayMonitorTests.swift
    ├── DockControllerTests.swift
    ├── HotkeyBindingTests.swift  # Modifier normalisation, matching, display formatting
    ├── URLCommandTests.swift     # smartdock:// parsing + rejection
    ├── AppleScriptCommandTests.swift  # Apple Event codes + .sdef parity
    └── DiagnosticReportTests.swift
Resources/
    ├── Info.plist                # Version, LSUIElement, URL types, sdef reference
    ├── SmartDock.sdef            # AppleScript dictionary (copied in by `make app`)
    └── SmartDock.entitlements    # Apple Events + scripting targets
.swift-format                     # Formatting rules — enforced by `make lint` in CI
```

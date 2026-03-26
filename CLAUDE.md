# CLAUDE.md

Project instructions for Claude Code. Follow these exactly.

## Build & Run

```bash
make build          # swift build -c release
make test           # swift test --parallel
make app            # build + icon + .app bundle (ad-hoc signed)
make run            # build + bundle + open
make clean          # remove build artifacts
```

Single test:
```bash
swift test --filter SmartDockTests.SmartDockServiceTests/testStartBeginsMonitoring
```

## Version & Release

```bash
make bump V=1.3.0   # update version in Makefile + Info.plist, increment build number
make release        # commit + build + zip + gh release create (uses --generate-notes)
make install        # copy .app to /Applications
make fix            # xattr -cr + codesign (fix Gatekeeper quarantine)
```

Version is defined in two places — keep them in sync (use `make bump`):
- `Makefile` line 6: `VERSION := x.y.z`
- `Resources/Info.plist`: `CFBundleShortVersionString` + `CFBundleVersion` (build number)

## Architecture

Swift Package (swift-tools-version 6.0), two targets: **SmartDockCore** (testable logic) and **SmartDock** (AppKit UI). Platform: macOS 14+, Swift 6 strict concurrency.

### Core layer (`Sources/SmartDockCore/`)

| File | Responsibility |
|---|---|
| `DockConfiguration.swift` | `DockConfiguration` value type (position, autohide, icon size, magnification). `UserPreferences` persists per-mode configs via UserDefaults. `DockPosition` enum. |
| `DisplayMonitor.swift` | Detects external monitor connect/disconnect via `CGDisplayRegisterReconfigurationCallback`. Debounces (1s settle delay). Filters by add/remove/enable/disable CG flags only — ignores space transitions. Conforms to `DisplayMonitoring`. |
| `DockController.swift` | Applies `DockConfiguration` via `NSAppleScript` → System Events. Each property in its own `tell` block (isolated failure). Reads current config via `UserDefaults(suiteName: "com.apple.dock")`. Conforms to `DockControlling`. |
| `SmartDockService.swift` | Orchestrator: reads `UserPreferences`, applies appropriate config based on display state. Has `SmartDockServiceDelegate`. |
| `Log.swift` | Centralized `Logger` API. Subsystem `com.smartdock.app`. |

### App layer (`Sources/SmartDock/`)

| File | Responsibility |
|---|---|
| `App.swift` | `@main` AppDelegate with manual `NSApplication` run loop (no storyboards). Checks Accessibility on launch. |
| `StatusBarController.swift` | Menu bar icon (`dock.rectangle` SF Symbol) + dropdown menu. Implements `NSMenuDelegate`, `SmartDockServiceDelegate`. |
| `SettingsWindow.swift` | Glass NSWindow (`NSVisualEffectView`), segmented control for External/Built-in modes. Position icon picker, sliders (save on mouseUp only), autohide, magnification. General: Launch at Login, Sync from System. |
| `LaunchAtLogin.swift` | `SMAppService.mainApp` wrapper. |
| `AccessibilityChecker.swift` | `AXIsProcessTrusted()` check + `AXIsProcessTrustedWithOptions` prompt. |

### Tests (`Tests/SmartDockTests/`)

- `Mocks.swift` — `MockDisplayMonitor`, `MockDockController`, `MockServiceDelegate`
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
- 4-space indentation (Swift standard)
- Opening brace on same line: `func foo() {`
- Align multiline function parameters vertically
- Trailing commas in multi-line arrays/dictionaries
- No semicolons
- Blank line between `// MARK: -` sections
- Max line length: ~120 characters (soft limit, prefer readability over strict wrapping)
- Use string interpolation `"\(value)"` not concatenation `"" + String(value)`, except for long multi-part log messages where `+` improves readability

### Swift Patterns Used in This Project
- **Protocol + concrete class** — define protocol first (`DockControlling`), then implementation (`DockController`). All external dependencies consumed via protocol.
- **Delegate pattern** — `SmartDockServiceDelegate` with `weak var delegate`. Delegate methods prefixed with subject: `serviceDidUpdateState(_:hasExternal:)`.
- **Value types for configuration** — `DockConfiguration` is a `struct`, immutable after init. Create new instance to change values.
- **Singleton via static let** — `UserPreferences.shared` with `private init()`. Only for app-wide state, never for testable services.
- **Extensions for helpers** — `private extension Int { func clamped(to:) }`, `private extension Bundle { var shortVersion }`. Keep helpers close to usage, private when single-file.
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
- Menu bar app: `NSApp.setActivationPolicy(.accessory)` + `LSUIElement = true`. No Dock icon.
- Glass/vibrancy: `NSVisualEffectView` with `.hudWindow` (window) or `.popover` (cards) material.
- Use `NSLayoutConstraint.activate([...])` for batch constraint activation — never `constraint.isActive = true` one by one.
- Slider values: update label during drag (`isContinuous = true`), but save/apply only on `mouseUp` (check `NSApp.currentEvent?.type == .leftMouseUp`).
- SF Symbols: always provide programmatic fallback for icons. Set `isTemplate = true` for menu bar icons.

### AppleScript / System Events
- Each Dock property (`autohide`, `position`, `dock size`, `magnification`, `magnification size`) is set in its **own** `tell application "System Events" / tell dock preferences` block. Never combine them — if one fails, others still apply.
- No `killall Dock`. AppleScript via System Events updates the Dock gracefully.
- Pixel sizes (16-128) must be converted to AppleScript scale (0.0-1.0) via `pixelsToAppleScriptScale()`.

### CoreGraphics Display Callbacks
- Use `CGDisplayRegisterReconfigurationCallback` — event-driven, no polling/timers.
- Filter the C callback: only react to **add/remove/enable/disable** flags (`0x10 | 0x20 | 0x100 | 0x200`). Ignore mode changes, moves, desktop shape changes — these fire during Mission Control and fullscreen transitions.
- Ignore `beginConfigurationChange` flag (rawValue 1) — react only to completion.
- Debounce with 1-second settle delay before checking display count. CG fires multiple callbacks during transitions.
- Track `lastExternalCount` — only fire `onConfigurationChanged` when the external display count **actually** changes.
- `CGDisplayIsBuiltin()` distinguishes built-in from external displays.

### UserDefaults
- App preferences: `UserDefaults.standard` with `com.smartdock.` prefix.
- Reading system Dock config: `UserDefaults(suiteName: "com.apple.dock")` — read-only, never write to this domain.
- Use `defaults.object(forKey:) != nil` to check if a key exists (`.bool(forKey:)` returns `false` for missing keys).

### Testing
- Always use protocol-based dependency injection — never instantiate `DisplayMonitor` or `DockController` directly in tests.
- Mock classes live in `Tests/SmartDockTests/Mocks.swift`.
- `MockDisplayMonitor.simulateDisplayChange(externalCount:)` triggers the callback chain.
- Tests use `swift test --parallel` — ensure tests are independent with no shared mutable state.

### Logging
- Use `Log.info()`, `Log.error()`, `Log.displayChange()` — never `print()`.
- All log output goes through `Logger` API (visible in Console.app, filter by `com.smartdock.app`).

## Entitlements & Permissions

- `com.apple.security.automation.apple-events` — required for NSAppleScript -> System Events
- `com.apple.security.scripting-targets` scoped to `com.apple.systemevents.dock.preferences`
- Sandbox: **off** (`com.apple.security.app-sandbox = false`)
- `LSUIElement = true` in Info.plist (no Dock icon)
- Accessibility: `AXIsProcessTrusted()` — prompt once on first launch, don't re-prompt if already granted

## File Structure

```
Sources/
├── SmartDockCore/
│   ├── DockConfiguration.swift   # DockConfiguration + UserPreferences + DockPosition
│   ├── DisplayMonitor.swift      # CG callback + debounce + flag filtering
│   ├── DockController.swift      # AppleScript per-property Dock control
│   ├── SmartDockService.swift    # Orchestrator: display state -> dock config
│   └── Log.swift                 # Logger wrapper
└── SmartDock/
    ├── App.swift                 # @main, manual NSApplication run loop
    ├── StatusBarController.swift # Menu bar icon + dropdown
    ├── SettingsWindow.swift      # Glass settings (Auto Layout, programmatic)
    ├── LaunchAtLogin.swift       # SMAppService wrapper
    └── AccessibilityChecker.swift
Tests/SmartDockTests/
    ├── Mocks.swift               # MockDisplayMonitor, MockDockController, MockServiceDelegate
    ├── SmartDockServiceTests.swift
    ├── DisplayMonitorTests.swift
    └── DockControllerTests.swift
Resources/
    ├── Info.plist                # CFBundleShortVersionString + CFBundleVersion
    └── SmartDock.entitlements    # Apple Events + scripting targets
```

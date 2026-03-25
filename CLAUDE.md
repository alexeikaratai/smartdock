# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
make build          # swift build -c release
make test           # swift test --parallel
make app            # build + generate icon + create .app bundle (ad-hoc signed)
make run            # build + create bundle + open app
make clean          # remove build artifacts
```

Single test (via swift CLI):
```bash
swift test --filter SmartDockTests.SmartDockServiceTests/testStartBeginsMonitoring
```

## Architecture

Swift Package (swift-tools-version 6.0) with two targets: **SmartDockCore** (testable business logic) and **SmartDock** (AppKit UI layer). Platform: macOS 14+, Swift 6 strict concurrency.

### Core layer (`Sources/SmartDockCore/`)

- **DockConfiguration** — value type for full Dock preferences: position (bottom/left/right), autohide, icon size, magnification, magnification size. Also contains `UserPreferences` for persisting per-mode configs via UserDefaults.
- **DisplayMonitor** — detects external monitor connect/disconnect via `CGDisplayRegisterReconfigurationCallback` (event-driven, no polling). Conforms to `DisplayMonitoring` protocol. `@MainActor`.
- **DockController** — applies `DockConfiguration` via `NSAppleScript` targeting System Events. Each property (position, autohide, size, magnification) is set in a separate AppleScript `tell` block so individual failures don't block others. Also reads current system config via `UserDefaults(suiteName: "com.apple.dock")`. Conforms to `DockControlling` protocol.
- **SmartDockService** — orchestrator: reads `UserPreferences` to determine which `DockConfiguration` to apply based on external/built-in display state. Has `SmartDockServiceDelegate`. `@MainActor`.
- **Log** — centralized logging via `Logger` API (macOS 14+). Subsystem `com.smartdock.app`.

### App layer (`Sources/SmartDock/`)

- **App.swift** — `@main @MainActor` AppDelegate with explicit `static func main()` for manual `NSApplication` run loop (no storyboards/nibs). Checks Accessibility permission on launch.
- **StatusBarController** — menu bar icon (`dock.rectangle` SF Symbol with programmatic fallback) with dropdown: version header, status, enable/disable, refresh, settings (⌘,), quit. Implements `NSMenuDelegate` and `SmartDockServiceDelegate`.
- **SettingsWindow** — Auto Layout NSWindow with glass effect (`NSVisualEffectView`), segmented control (External Monitor / Built-in Only). Each mode has: position icon picker (programmatic drawing), autohide checkbox, icon size slider, magnification toggle + slider. General section: Launch at Login, Sync from System. Slider saves on mouseUp only (not during drag). Only applies to Dock if edited mode matches current display state.
- **LaunchAtLogin** — wraps `SMAppService.mainApp` for login item registration.
- **AccessibilityChecker** — checks `AXIsProcessTrusted()` on launch. Uses `AXIsProcessTrustedWithOptions` for system trust dialog. Only prompts if not already granted.

### Key patterns

- Protocols (`DisplayMonitoring`, `DockControlling`) enable dependency injection; tests use `MockDisplayMonitor` and `MockDockController` from `Tests/SmartDockTests/Mocks.swift`.
- All core and UI types are `@MainActor`-isolated (Swift 6 strict concurrency).
- Two-mode preferences: `UserPreferences.shared.externalConfig` and `.builtinConfig` persist per-mode dock settings.
- `DockController.apply(_:)` sets each Dock property via its own AppleScript `tell` block (isolated failure) — no `killall Dock` needed.
- `DisplayMonitor` filters spurious CG reconfiguration callbacks by tracking `lastExternalCount` — only fires `onConfigurationChanged` when the external display count actually changes.
- `make app` includes ad-hoc codesigning (`codesign --sign -`) so the app opens without Gatekeeper issues.

## Entitlements & Permissions

- `com.apple.security.automation.apple-events` — required for NSAppleScript → System Events
- `com.apple.security.scripting-targets` scoped to `com.apple.systemevents.dock.preferences`
- Sandbox is **off** (`com.apple.security.app-sandbox = false`)
- `LSUIElement = true` in Info.plist (no Dock icon)

## File Structure

```
Sources/
├── SmartDockCore/
│   ├── DockConfiguration.swift   # DockConfiguration model + UserPreferences
│   ├── DisplayMonitor.swift
│   ├── DockController.swift
│   ├── SmartDockService.swift
│   └── Log.swift
└── SmartDock/
    ├── App.swift
    ├── StatusBarController.swift
    ├── SettingsWindow.swift
    ├── LaunchAtLogin.swift
    └── AccessibilityChecker.swift
Tests/SmartDockTests/
    ├── Mocks.swift
    ├── SmartDockServiceTests.swift
    ├── DisplayMonitorTests.swift
    └── DockControllerTests.swift
```

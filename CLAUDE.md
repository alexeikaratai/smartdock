# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
make build          # swift build -c release
make test           # swift test --parallel
make app            # build + generate icon + create .app bundle
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

- **DisplayMonitor** — detects external monitor connect/disconnect via `CGDisplayRegisterReconfigurationCallback` (event-driven, no polling). Conforms to `DisplayMonitoring` protocol. `@MainActor`.
- **DockController** — toggles Dock autohide via precompiled cached `NSAppleScript` targeting System Events. Conforms to `DockControlling` protocol.
- **SmartDockService** — orchestrator: when external display is detected, disables Dock autohide; when only built-in display remains, enables autohide. Has a `SmartDockServiceDelegate` for notifying the UI layer. `@MainActor`.
- **Log** — centralized logging via `Logger` API (macOS 14+). Subsystem `com.smartdock.app`, categories: general, display, dock.

### App layer (`Sources/SmartDock/`)

- **App.swift** — `@main @MainActor` AppDelegate with explicit `static func main()` for manual `NSApplication` run loop (no storyboards/nibs). Sets `.accessory` activation policy (menu bar only, no Dock icon).
- **StatusBarController** — menu bar icon (`dock.rectangle` SF Symbol with programmatic fallback) with dropdown: version header, status, enable/disable toggle, refresh, settings, quit. Implements `NSMenuDelegate` for dynamic state updates and `SmartDockServiceDelegate`.
- **SettingsWindow** — NSWindow built entirely with Auto Layout. Shows app icon, name, version, creator (Alex Karatai), and settings: Enable SmartDock toggle + Launch at Login checkbox.
- **LaunchAtLogin** — wraps `SMAppService.mainApp` for login item registration.
- **AccessibilityChecker** — checks `AXIsProcessTrusted()` on launch, prompts user to grant Accessibility permission with direct link to System Settings.

### Key patterns

- Protocols (`DisplayMonitoring`, `DockControlling`) enable dependency injection; tests use `MockDisplayMonitor` and `MockDockController` from `Tests/SmartDockTests/Mocks.swift`.
- All core and UI types are `@MainActor`-isolated (Swift 6 strict concurrency). The CG display callback dispatches back to main queue with `@MainActor` annotation.
- Tests are `@MainActor`-annotated to match production code isolation.
- The app requires Accessibility permission to send AppleEvents to System Events for Dock control.
- `DockController` caches two precompiled `NSAppleScript` instances (show/hide) to avoid repeated compilation overhead.

## Entitlements & Permissions

- `com.apple.security.automation.apple-events` — required for NSAppleScript → System Events
- `com.apple.security.scripting-targets` scoped to `com.apple.systemevents.dock.preferences`
- Sandbox is **off** (`com.apple.security.app-sandbox = false`)
- `LSUIElement = true` in Info.plist (no Dock icon)

## File Structure

```
Sources/
├── SmartDockCore/
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

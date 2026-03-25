# SmartDock

Menu bar app for macOS that automatically toggles Dock visibility based on external monitors:

- **External monitor connected** → Dock is always visible
- **No external monitors** → Dock auto-hides

Event-driven — no timers, no polling. Uses `CGDisplayRegisterReconfigurationCallback` for instant detection.

## Requirements

- macOS 14.0+ (Sonoma)
- Swift 6.0+
- Xcode 16+ / Command Line Tools (`xcode-select --install`)

## Quick Start

```bash
# Build and run
make run

# Or step by step
make build      # Compile
make icon       # Generate app icon
make app        # Create .app bundle
open build/SmartDock.app
```

## Run Tests

```bash
make test
```

## Features

- **Menu bar icon** — `dock.rectangle` SF Symbol, adapts to light/dark theme
- **Settings window** (⌘,) — Enable/Disable, Launch at Login, version info, about section
- **Launch at Login** — via `SMAppService` (Apple's recommended API)
- **Accessibility check** — prompts on first launch if permission not granted
- **No Dock icon** — lives entirely in the menu bar (`LSUIElement = true`)

## Architecture

```
Sources/
├── SmartDockCore/                # Testable business logic
│   ├── DisplayMonitor.swift          # CGDisplay callback — detects monitor changes
│   ├── DockController.swift          # AppleScript — toggles Dock autohide smoothly
│   ├── SmartDockService.swift        # Orchestrates monitor → dock logic
│   └── Log.swift                     # Logger API wrapper (macOS 14+)
└── SmartDock/                    # App layer
    ├── App.swift                     # @main entry point
    ├── StatusBarController.swift     # Menu bar icon & dropdown menu
    ├── SettingsWindow.swift          # Settings window (Auto Layout)
    ├── LaunchAtLogin.swift           # SMAppService wrapper
    └── AccessibilityChecker.swift    # Permission check & prompt
```

**Key design decisions:**
- Swift 6 with strict concurrency — `@MainActor` on all UI and service types
- Protocols (`DisplayMonitoring`, `DockControlling`) for testability via dependency injection
- `CGDisplayRegisterReconfigurationCallback` instead of `NSNotification` — lower level, more reliable
- `NSAppleScript` with precompiled cached scripts — smooth animation, no Dock restart
- `SMAppService` for Launch at Login — Apple's recommended API since macOS 13
- `Logger` API for logging — visible in Console.app, filter by `com.smartdock.app`

## Permissions

On first launch, SmartDock checks for Accessibility permission and shows a dialog with a direct link to System Settings → Privacy & Security → Accessibility. This is required to control Dock preferences via System Events.

## Installation

### From GitHub Release (unsigned)

Download `SmartDock.app` from [Releases](https://github.com/alexkaratai/smartdock/releases). macOS will block unsigned apps downloaded from the internet. To open:

```bash
xattr -cr SmartDock.app
open SmartDock.app
```

Or: right-click → Open → Open in the dialog.

### From Homebrew

```bash
brew tap alexkaratai/tap
brew install smartdock
```

## Distribution

### Notarized DMG (recommended for sharing)

```bash
# Set your signing identity
export TEAM_ID=ABCDE12345
export SIGN_ID="Developer ID Application: Your Name (ABCDE12345)"

make notarize
# → build/SmartDock-1.0.0.dmg (signed + notarized)
```

### App Store

This app uses `com.apple.security.automation.apple-events` which is allowed with justification in App Store review. The `NSAppleEventsUsageDescription` in Info.plist explains why.

Note: App Store requires sandbox (`com.apple.security.app-sandbox = true` in entitlements). You'll need to test that AppleScript still works within the sandbox, or switch to an alternative mechanism.

## Author

Alex Karatai

## License

MIT

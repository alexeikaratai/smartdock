# Changelog

All notable changes to SmartDock are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.1] — 2026-08-16

### Fixed
- Forcing a profile now sticks. "Apply Built-in Profile" applied the requested profile
  and then immediately re-derived one from the connected displays, undoing it within the
  same call — so forcing built-in while an external monitor was attached did nothing,
  which is the only situation where forcing is useful. Affected all three entry points
  equally: hotkey, `smartdock://switch/builtin` and `tell application "SmartDock" to
  switch to builtin`. The override now holds until the next display change or refresh.
- A profile with magnification **off** no longer loses its magnified-size setting.
  `apply` deliberately skips that property while magnification is off — the value is
  invisible and writing it makes the Dock flash — but the system-sync check compared
  it anyway. Every apply therefore read the system back as an *external* edit and
  overwrote the stored value. The two now share one definition, and a test pins them
  together so they cannot drift again.

### Changed
- The "which settings actually differ" decision moved out of `DockController` into
  `DockConfiguration.differences(from:)`. It is the part with the edge cases, and it
  could not be tested through a controller that talks to the live System Events.
- `DockController` takes its preferences domain as an argument, so tests read and
  write a scratch domain instead of the developer's real `com.apple.dock`.
- The 0.01 size tolerance is now `DockConfiguration.sizeTolerance`, defined once
  rather than written out at three call sites.

## [2.1.0] — 2026-08-09

### Added
- URL scheme for automation — `smartdock://refresh`, `smartdock://switch/external`,
  `smartdock://switch/builtin`, `smartdock://toggle-autohide`, `smartdock://settings`.
  Works from Raycast, Alfred, Shortcuts.app and shell (`open smartdock://refresh`).
- **Copy Diagnostic Info** button in the About tab — version, macOS build, permission
  status and display state to the clipboard for bug reports.
- Clicking a profile-switch notification now opens Settings.
- **AppleScript support** — SmartDock ships a scripting dictionary, so it can be
  driven from Script Editor, `osascript`, Shortcuts.app and Automator:
  ```applescript
  tell application "SmartDock"
      refresh
      switch to external
      toggle autohide
      show settings
  end tell
  ```
- `CONTRIBUTING.md` and a pull request template.
- 21 tests covering hotkey normalisation, matching and display formatting, plus 8
  covering the AppleScript profile vocabulary — including a check that the four-character
  codes in `SmartDock.sdef` and in Swift still agree.

### Changed
- Code formatting is now enforced by `swift-format` (bundled with Xcode — still no
  external dependencies). `make format` fixes, `make lint` checks, and CI fails on any
  deviation. Hand-aligned columns are gone as a result; the formatter is the style guide.
- `make coverage` prints a per-file coverage table, and CI publishes it to the run
  summary.
- AppleScript, `smartdock://` URLs and global hotkeys now enter through a single
  `AppDelegate.performCommand(_:)`. Commands that arrive before launch finishes are
  queued rather than dropped — previously only URLs were, and only after a crash fix.
- Hotkey matching and recording now share one definition in `SmartDockCore`
  (`HotkeyBinding.relevantModifiers` / `normalize` / `matches` / `displayString`).
  Previously the modifier mask was written out separately in `HotkeyManager` and
  `HotkeyRecorder`; if the two had drifted apart, recorded shortcuts would have
  silently stopped firing.
- `ExistentialAny` and `MemberImportVisibility` are enabled package-wide. Both become
  the default in a later language mode, so the migration is done rather than pending —
  and a bare existential now breaks the build instead of accumulating silently.

### Security
- `ci.yml` declares `permissions: contents: read`. It previously inherited the
  repository default, which can include write access — more than a job that runs
  code from pull requests should ever hold.

## [2.0.1] — 2026-08-02

### Added
- CI now runs `make version-check` and builds the signed `.app` bundle, so icon
  generation, entitlements and ad-hoc signing break on the PR instead of mid-release.
- Dependabot watches GitHub Actions and opens one grouped PR per month.

## [2.0.0] — 2026-07-26

### Changed
- Settings UI split into reusable components under `Sources/SmartDock/Views/`:
  `AboutTabView`, `AccessibilityWarningView`, `PositionPicker`, `PositionIcon`, `UI`.
- Hotkey capture extracted from `SettingsWindow` into a dedicated `HotkeyRecorder`.

### Added
- Accessibility warning banner on the Shortcuts tab with **Open System Settings**
  and **Reset Permission** actions.

## [1.9.3] — 2026-07-14

### Added
- Menu bar tooltip shows the active profile, dock position and visibility.
- `make logs` streams live app logs.

### Changed
- Escape closes the Settings window (skipped while recording a hotkey).

## [1.9.0] — 2026-05-22

### Fixed
- `externalDisplayCount()` now skips sleeping and inactive displays, so clamshell
  mode and phantom USB-C hub connections no longer count as an external monitor.

## [1.8.9] — 2026-05-09

### Added
- `AppUpdateWatcher` detects a replaced binary (Homebrew upgrade) and offers to relaunch.
- `AppRelauncher` waits for the current process to exit before starting the new one,
  so an update or permission reset never leaves two instances running.
- Guided Accessibility recovery: after **Reset Permission** the app reopens on the
  Shortcuts tab, opens System Settings, and relaunches itself once permission is granted.

## [1.8.5] — 2026-05-03

### Fixed
- Global hotkeys stopped working after a Homebrew upgrade because ad-hoc re-signing
  resets the Accessibility grant. Monitors are now rebuilt whenever the app becomes
  active, picking up permission changes without a manual restart.

## [1.8.1] — 2026-04-12

### Changed
- Settings redesigned as a tabbed window: **Settings**, **Shortcuts**, **About**.
  The standalone About window was removed.

## [1.7.0] — 2026-04-07

### Added
- Onboarding screen on first launch.
- About window with version and project links.

### Changed
- Accessibility is prompted only on first launch, so Homebrew updates no longer
  re-trigger the system dialog.

## [1.6.0] — 2026-04-05

### Added
- Global keyboard shortcuts (`HotkeyManager`) for toggling autohide, refreshing,
  applying either profile and opening Settings.
- macOS banner notifications on profile switch, with a 3-second cooldown.
- Two-way sync with System Settings via KVO on `com.apple.dock`, guarded against
  feedback loops by comparing against the last applied configuration.

## [1.5.0] — 2026-04-01

### Changed
- Dock sizes stored on the native 0.0–1.0 scale instead of pixels, removing
  pixel → scale → pixel rounding drift. Existing preferences are migrated.

### Removed
- Space-change observer — AppleScript dock changes trigger space notifications,
  which caused an infinite feedback loop.

---

Releases before 1.5.0 are listed on the
[GitHub Releases page](https://github.com/alexeikaratai/smartdock/releases).

[Unreleased]: https://github.com/alexeikaratai/smartdock/compare/v2.0.1...HEAD
[2.0.1]: https://github.com/alexeikaratai/smartdock/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/alexeikaratai/smartdock/compare/v1.9.3...v2.0.0
[1.9.3]: https://github.com/alexeikaratai/smartdock/compare/v1.9.0...v1.9.3
[1.9.0]: https://github.com/alexeikaratai/smartdock/compare/v1.8.9...v1.9.0
[1.8.9]: https://github.com/alexeikaratai/smartdock/compare/v1.8.5...v1.8.9
[1.8.5]: https://github.com/alexeikaratai/smartdock/compare/v1.8.1...v1.8.5
[1.8.1]: https://github.com/alexeikaratai/smartdock/compare/v1.7.0...v1.8.1
[1.7.0]: https://github.com/alexeikaratai/smartdock/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/alexeikaratai/smartdock/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/alexeikaratai/smartdock/releases/tag/v1.5.0

# Changelog

All notable changes to SmartDock are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.4.0] — 2026-08-27

### Changed
- The test suite moved from XCTest to **Swift Testing** — 15 suites, `@Test` and
  `#expect` throughout. Failures now name the expression that failed and the line it
  is on, and cases that only differed by their input became parameterised tests.
- Tests **run in parallel** again. They could not before: `UserPreferences.shared` is a
  singleton, and suites that reset it wiped state out from under each other, so the
  project banned `--parallel` outright. `UserPreferences` now takes its `UserDefaults`
  as an argument, and each test owns a throwaway domain — the shared state is gone
  rather than scheduled around.
- 18 tests covering the settings store, which had none: first-launch seeding, the
  guard that stops it overwriting configured profiles, and the pixel→scale migration.
  `DockConfiguration.swift` went from 73% to 97% covered.
- The AppleScript sent for each dock property is now asserted. Only `screen edge` was
  ever exercised; a typo in `set magnification size to` would have run, reported
  success and changed nothing — the same silent failure that took a full session to
  diagnose for `autohide`. Each of the five is pinned, along with the rule that every
  property goes in its own `tell` block so one refusal cannot take the others down.
- The KVO path that imports changes made in System Settings is covered end to end,
  against a scratch preferences domain rather than the developer's real Dock. That
  includes the loop guard — the check that tells SmartDock's own writes, echoed back
  through the observer, from a genuine edit. `DockController.swift` went from 44% to
  96% covered, and the suite overall from 75% to 90%.
- `DisplayMonitor` takes its display count and settle delays as arguments, so the
  debounce and change filter around the CoreGraphics callback are covered without a
  monitor to plug in: a burst of callbacks collapsing into one check, transient counts
  mid-transition being ignored, and the wake re-check surviving a stream of unrelated
  callbacks. 53% to 99% — including the CoreGraphics callback itself, which decides
  whether an event is worth reacting to and recovers the monitor from an opaque
  pointer. The suite overall reached 98%.
- Tests keep their preferences in memory instead of in throwaway `UserDefaults`
  suites. A real suite domain belongs to `cfprefsd`, a separate daemon that flushes
  it on its own schedule — including after the test process has exited — so no
  in-process cleanup could win the race, and a few hundred runs left thousands of
  plists in `~/Library/Preferences`. A run now leaves nothing behind.
- The migration from pixel sizes to the 0.0–1.0 scale lost a branch that could never
  run. It read the stored value as `Int` when the `Double` cast failed, but
  UserDefaults keeps numbers as `NSNumber`, which bridges to `Double` whichever way
  the value was written — so the fallback was unreachable.

Coverage across `SmartDockCore` finished at 98% of lines, with nine of twelve files
complete. What remains is the AppleScript call into live System Events and the branch
that runs only if CoreGraphics refuses to register a callback — neither reachable
without driving the real system.
- `LogExport.defaultFileName` reads date fields directly instead of unwrapping an
  optional `DateComponents`. The five `?? 0` fallbacks it needed could not be reached
  for a real date, and would have produced `SmartDock-log-0000-00-00-0000.txt` if they
  ever were.

### Fixed
- A stopped `DisplayMonitor` no longer reports display changes. `handleWake` had always
  checked `isRunning`; `handleReconfiguration` had not, so a CoreGraphics callback
  already queued when `stop()` ran could still fire afterwards. The service's own
  `isEnabled` check absorbed it, so nothing was visibly wrong — but the monitor did not
  honour its own state.

## [2.3.0] — 2026-08-23

### Added
- **Export Logs…** in the About tab — writes SmartDock's own log of the last 24 hours
  to a file. Pairs with **Copy Diagnostic Info**: that says what the settings are,
  this says what actually happened, including whether the Dock honoured each change.
  The user's home directory is replaced with `~` before the file is written, so an
  exported log can be attached to a public issue without carrying the account name.

### Fixed
- Log messages are recorded at **notice** level instead of info, so they survive to
  be read back. macOS keeps info-level messages in a memory buffer and never writes
  them to the persistent store — `log show` and the new export returned almost
  nothing but errors, which read as though the app had barely logged at all.

## [2.2.0] — 2026-08-17

### Added
- SmartDock now checks whether the Dock actually accepted a change, instead of
  trusting AppleScript. `NSAppleScript` reports success as soon as the script *runs* —
  System Events can accept it and quietly not honour it, and the two are
  indistinguishable at the call site. The Dock is read back a second later and any
  setting that did not land is logged and shown in **Copy Diagnostic Info**, flagged
  the way a missing permission is. Without this, "the app says it applied but nothing
  happened" was undiagnosable from a bug report.

### Fixed
- A profile switch suppressed by the notification cooldown no longer counts as
  announced. The state was recorded before the cooldown check, so a switch the user
  was never shown was treated as already delivered — and the next genuine switch back
  to it was dismissed as a duplicate, leaving them never told at all.

### Changed
- Timing and queueing logic moved from the app target into `SmartDockCore`, where
  tests can reach it: hotkey rate limiting, the notification cooldown, and the queue
  that holds commands arriving before launch finishes. All three take the current time
  as an argument, so the interval edges are asserted exactly rather than by sleeping.

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

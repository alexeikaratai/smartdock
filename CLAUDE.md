# CLAUDE.md

Project instructions for Claude Code. Follow these exactly.

## Working on a Task

One task at a time, carried through these steps in order. A step is not done because it
was started; each has a visible output. The tree ends up ready for the **user** to commit
and release — see the last step.

### 1. Understand the task

Restate it: what changes for a person, what is in scope, what is explicitly not. If two
readings would lead to different work, ask now. Check what the change does for the people
who use this — per-monitor profiles was planned twice before reading the user's stored
profiles showed it would change nothing for them.

### 2. Measure before planning

Everything load-bearing is checked against the running system before it reaches a plan.
A plan built on an assumption is worth nothing. Things here that looked obvious and were
not: `mineffect`/`launchanim` are absent until changed, so `bool(forKey:)` lies; two
identical monitors differ only by serial; `show recents` needs no `killall`; `autohide
menu bar` lives in `NSGlobalDomain`; App Intents extraction needs three undocumented
flags. Each was found by looking, not by recalling.

State plainly which claims are measured and which are knowledge. "I believe" and
"I checked" are different words; never let one stand in for the other.

### 3. Plan

What the change is, which files it touches, roughly how long, what could break, what
stays out of scope. Where there is a real choice, options with a recommendation — not a
survey.

### 4. Challenge the plan, then get a decision

Before writing code, attack the plan: what did it assume, which call sites does it not
mention, what would a user see that they did not ask for. Revise it. Then wait for a
decision on anything that changes behaviour users already rely on. The tab split planned
to move "Sync from System" to General; reading it showed it depends on the mode control
above it, and the plan changed before a line was written.

### 5. Implement — to the plan

Match the surrounding code. Prefer a structural fix over a patch — see **A list repeated
in two places will drift** under Principles. Every deviation from the plan is noted as it
happens, not reconstructed afterwards.

### 6. Reconcile with the plan

Read the plan against the diff and answer three questions explicitly: planned and done;
planned and **not** done, and why; done and **not** planned, and why. The third group is
where unreviewed behaviour hides — the settings-window plan had five items, and this step
surfaced a sixth that was more serious than the five.

### 7. Regressions and compatibility

Green tests are the floor, not the ceiling. Read every call site the change touches and
ask what silently behaves differently now; one session found four regressions after the
suite was green. Compatibility is checked on three axes: **stored data** (profiles from
earlier versions lack keys added since — seed from the live system, see Principles),
**toolchains** (CI and the dev machine run different Xcodes, see Gotchas), **frozen
contracts** (Apple Event codes, `AppEnum` raw values, intent identifiers, `smartdock://`
verbs — stored in users' scripts and shortcuts, never renamed).

Where tests cannot reach, verify live: build, run the app, read the unified log with
`/usr/bin/log` (zsh shadows the name), compare the Dock's settings before and after. Then
put the machine back: quit the test build, `lsregister -u` it, relaunch the installed one,
restore any setting changed.

### 8. Tests

In this order: the suite passes; anything broken is fixed, not skipped; new logic in
`SmartDockCore` gets tests; a new guard is proven by **mutation** — break it, watch the
intended test fail, restore, re-run. A fixture that leaves a field at its default cannot
catch that field being dropped. The `SmartDock` target is an executable outside the test
bundle: say so rather than implying coverage, verify it by running. `SmartDockUI` is in
the bundle — a view with a settable, readable state (`DockProfileForm.configuration`) is
tested there; logic still moves into Core when it can. A test that waits for the main
queue waits for the event (`waitUntil`), never a fixed time.

### 9. Final consistency pass

Nothing ships while any two of these disagree: the code, this file, `CHANGELOG.md`,
`README.md`, the diff's comments. Every make target runs — all of them, since
`make coverage` broke on Xcode 27 while `swift test` passed. No document still describes
the old behaviour. Every symbol a document names exists. The CHANGELOG entry sits under
`## [Unreleased]`, says what changed for a person and why, and covers what step 6 found.

### 10. Stop at the commit

**Claude does not commit, push, tag or release.** Leave the working tree ready and say
what is in it, file by file. Bumping, committing and `make release` are the user's, one
task per version, so a release traces to a single change.

## Principles

The rules this codebase runs on. Each carries the case that produced it, so the reason
survives the next refactor. A change that breaks one is a change to the design.

**One execution path.** Hotkeys, `smartdock://` URLs, AppleScript and Shortcuts are four
front doors into `AppDelegate.performCommand` — never four implementations. A fifth input
adds a door, not a behaviour.

**Nothing the system reports is taken on trust.** `NSAppleScript` returns success as soon
as the script *ran*. Every apply is read back and recorded (`DockApplyOutcome`); without
that, "the app says it applied but nothing happened" cannot be diagnosed from a report.

**An absent value is not a false one, and our default has to match theirs.** macOS writes
a preference only once it has been changed, so a missing key means *default*, not `false`.
A struct default that disagrees with what macOS holds when the key is absent makes every
apply push a redundant script — `aDefaultConfigAsksTheDockForNothing` pins it.

**A value the user never chose comes from their system, not from our defaults.** A setting
added today is absent from profiles saved yesterday; seeding it from struct defaults would
restyle a Dock someone had deliberately set. `backfillMissingSettings` reads the live Dock.
The same rule on a fresh install: both profiles are the Dock verbatim — it used to force
auto-hide on one and off on the other, and the first thing the app did was move a Dock
nobody had asked it to. Nothing changes until the person edits a profile.

**Break the build rather than write a note.** Agreement between two places is enforced by
an exhaustive switch where the compiler can reach — `HotkeyAction(URLCommand)`,
`push(_:of:)`, `ShortcutCoverage.intentType(for:)`, `DockProfileForm.binding(for:)`,
`store(_:of:forKey:)`/`restore(_:into:from:)` — and by a test or make target where it
cannot: `.sdef` parity, `anEditToEveryPropertyIsReported` (the KVO key list),
`everyPropertyIsReadFromItsDockKey` (`readSystemConfig` — its initialiser defaults every
argument, so a property it forgets to read compiles and returns *our* value),
`appintents-check`, `sdef-check`, `entitlements-check`, `version-check`.

**A list repeated in two places will drift.** `toggleAutohide` rebuilt the config field by
field and silently reset every setting it had not heard of; a `zip` against a literal list
quietly stopped checking two properties; the settings form read and wrote through two
separate lists until `DockProfileForm` put both directions of each field in one
`binding(for: DockProperty)`; `save`, `load`, `backfillMissingSettings` and `migrateMode`
each spelled the same ten settings out by hand until they shared `storageKey`, `store` and
`restore` — the backfill had drifted to five of the ten, so the next setting added would
have reached every saved profile as our default, and `load`'s hand-written absent-key rule
used `value > 0` for the two sizes and so could not keep a Dock deliberately set to 16px.
Prefer a copy helper (`DockConfiguration.with`) or drive the code from `allCases` with an
exhaustive switch.

**Report what is, not what was asked — but only where something is reported.** The menu
bar icon, the tooltip and the refusal notice reflect what the Dock actually holds,
reconciled after verification (`currentConfig`); the *stored* profile is left alone, since
the user still wants auto-hide and macOS merely would not do it right now. A **control**
sits on the other side: it reads `activeProfileConfig`, what the profile asks for. Reading
the observed state there cost reversibility — after a refusal the auto-hide toggle kept
re-requesting the same thing, so two presses left the setting flipped instead of back
where it started. Shipped in 2.8.1; the menu item's title and the position tick had the
same fault.

## Build & Run

```bash
make build / test / app / run / clean          # swift build -c release · swift test · bundle (ad-hoc signed) · open · clean
make format / lint / coverage                  # swift-format apply · check (CI gates) · llvm-cov table
make appintents / appintents-check             # generate Metadata.appintents · verify every intent reached it
make entitlements-check / sdef-check           # bundle carries the entitlements file · .sdef classes exist (both in app)
make bump V=1.2.3 / version-check / release    # version everywhere · verify refs · build + zip + gh release (clean tree)
make changelog-check / release-notes           # this version's notes exist · print them (the release body)
make install / fix                             # copy to /Applications · xattr -cr + codesign
make doctor / outdated / actions-check / logs  # env check · toolchain versions · Actions vs latest · live log
swift test --filter startBeginsMonitoring      # one test
```

## Version & Release

**Never edit a version by hand — always `make bump`.** The version is written in four
places — `Makefile` (source of truth), `Info.plist` (`CFBundleShortVersionString`, and
`CFBundleVersion` +1), README badge URL and alt, `CHANGELOG.md` dated section — and `bump`
is the only thing that knows all of them. `release.yml` calls `make bump` rather than
re-implementing it; add a fifth place to `bump` and `version-check` and CI follows.

**Never delete `## [Unreleased]`.** `bump` inserts the new section directly under it, so
whatever accumulated there becomes the release notes. `version-check` also guards the
CHANGELOG: a version may appear once, and an empty section for `VERSION` **warns** there
while `changelog-check` **fails**. The split is deliberate — `bump` opens the section
before the notes exist, but a published release with empty notes cannot be taken back.
2.5.0 shipped that way, with its notes under a version that never existed, and 2.8.1
repeated it exactly: the fatal check lived inside the `release` target, so the
tag-triggered workflow — which is the path an actual release takes — never reached it.
`changelog-check` is its own target now, called by `make release` and by `release.yml`
right after its `bump`. Docs use `V=1.2.3` as a placeholder so grepping the real version
finds only definitions.

## CI/CD

**`ci.yml`** (push to `main`/`dev`, PRs to `main`): concurrency per branch, SPM cache,
then `version-check` → `lint` → `coverage` → `swift build -c release` → `make app` +
`codesign --verify --strict`. Lint runs first so a formatting PR fails in seconds.
`coverage` replaces a bare `swift test` so the suite is not compiled twice; its step sets
`shell: bash` because the default runner shell has no `pipefail` and `| tee` would mask a
failure. `make app` is the only place `appintents-check`, `entitlements-check` and `sdef-check`
run, so a toolchain that breaks metadata extraction, a dropped entitlement or a scripting
class the dictionary cannot find fails the PR, not the release. `entitlements-check` reads
the sealed bundle back with `codesign -d --entitlements :-` and diffs it against
`Resources/SmartDock.entitlements` — the file is the only list of keys, so a new entitlement
needs no change to the check.

**`release.yml`** (`v*` tag): 🧪 Test → 🔨 Build → 🎉 Release → 🍺 Homebrew (updates Cask +
Formula in `alexeikaratai/homebrew-tap`). Build runs `make bump` for the tag, then
`make changelog-check` — so a tag whose notes were never written stops before anything is
published — and writes `make release-notes` into the artifact beside the zip. Release has
no checkout and could not produce them itself: the section for the tag exists only after
`bump`, in Build's working copy. Both paths publish that file as the body; until 2.8.1
they passed `--generate-notes`, which produced a bare compare link.

**`dependabot.yml`**: monthly grouped Actions bumps; no `swift` entry because there are no
SPM dependencies.

Both workflows set Xcode via `env.XCODE_PATH` at workflow level, never inline. Runner and
`XCODE_PATH` must agree — check the
[runner image readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
before bumping either. Actions are pinned by major (except `webfactory/ssh-agent`, a 0.x release pinned exactly);
`make actions-check` compares to latest — never write the
numbers into this file, they go stale.

## Known Build Gotchas

**SPM's output layout moved.** Swift ≤6.3 writes modules to `.build/release/Modules/`;
Swift 6.4 (Xcode 27) builds through swift-build, `.build/release` becomes a symlink to
`out/Products/Release`, the module is a bundle directory there, and the test bundle is
named after the target (`SmartDockTests.xctest`) not the package. Anything reaching into
`.build` by path breaks on one side — `make appintents` passes both `-I` paths,
`make coverage` locates `*.xctest`. The first break hid its real cause behind twelve
"missing file" errors because the recipe chained steps with `;`; it runs under `set -e`
now. The second was missed because only `swift test` was run: **when a toolchain changes,
run every make target.**

**`swift-format` in Xcode 27 requires `orderedImports.shouldGroupImports`.** Without it the
config fails to load and lint fails on every file. Set to `true` — the value that changes
no existing file — and ignored by the Xcode 26 formatter (synthesized `Decodable` skips
unknown keys, checked against its source), so one config serves both.

**CI cannot follow the dev machine.** No `macos-27` runner image exists and `macos-26` stops
at Xcode 26.6. Until then CI verifies the old layout and a developer on Xcode 27 the new —
and a green local suite is not proof. `make coverage` passed on Xcode 27 and failed to
compile on 26.6 over `let button = try #require(button("Export", in: view))`: inside a
`#require` expansion the older compiler resolves the call to the variable being declared
("cannot call value of non-function type"). **Never give a local the name of a function in
scope**, least of all inside a macro. Anything a test does that the compiler has opinions
about — macros, shadowing, inference — is verified by the next CI run, not by the local one.

**A workflow step creates what it writes into.** `make release-notes > build/notes.md`
worked on the dev machine and failed on the runner: `build/` is made by `make app`, which
comes later, and a developer always has one left over from the last build. The step does
`mkdir -p build` itself now. The same shape as the toolchain gap above — the local run was
green because the machine carried state a fresh checkout does not.

**Stale build after changing an initialiser used as a default argument** — e.g.
`SmartDockService.init(dockController: … = DockController())`. Link fails with `Undefined
symbols` and an unrelated `SwiftUICore.tbd` warning. `rm -rf .build && swift build`.

## Architecture

Swift Package (tools 6.2), three targets: **SmartDockCore** (logic, no UI),
**SmartDockUI** (the AppKit layer as a library, so tests can build a view and read it
back) and **SmartDock** (the executable: `App.swift`, `AppIntentsSupport.swift`,
`ScriptingSupport.swift` — the three that must carry the app's module name, because
intent identifiers are module-qualified and the `.sdef` binds `@objc` class names).
macOS 14+, Swift 6 strict concurrency, zero dependencies. `public` in UI is only what
those three files call.
Bundle inputs live in `Resources/`: `Info.plist`, `SmartDock.sdef`, `SmartDock.entitlements`,
and `AppIcon.icns`, which is git-ignored and regenerated by `make icon` (a prerequisite of
`app`) from `scripts/generate-icon.swift`. `make app` copies the plist, `.sdef` and `.icns` in
and applies the entitlements through `codesign`. README images are in `assets/`.

### Core (`Sources/SmartDockCore/`)

| File | Responsibility |
|---|---|
| `DockConfiguration.swift` | `DockConfiguration` value type: position, autohide, icon size (0.0–1.0 scale, `pixelsToScale`/`scaleToPixels`, 0.01 tolerance), magnification, `MinimizeEffect` genie/scale, `animatesLaunch`, `showsRecents`, `showsIndicators`, `minimizesToApplication` (absent-key defaults measured: indicators on, minimize-into-app off). `with(...)` copies with fields replaced — the guard against field-by-field rebuilds. `differences(from:)` is the apply diff, pure and tested. `UserPreferences` persists per-mode profiles plus flags and hotkeys, `prefs[profile]` by `DockProfile` — never `if external { externalConfig } else …` at a call site; `migrateIfNeeded` converts the pre-scale pixel keys and is called once from `applicationDidFinishLaunching`, not by `load`; `initializeDefaultsIfNeeded` makes both profiles the Dock as it is on a fresh install, so the first apply is a no-op; `backfillMissingSettings` fills keys an old profile predates from the live Dock. Every one of those four reaches a stored key through `storageKey(_:_:)` and a value through the exhaustive `store`/`restore` pair, so a property cannot be written without being read back or seeded; an absent key means *default* because `restore` returns the config untouched, never because a fallback was spelled out per field. `DockPosition`, `HotkeyBinding`. |
| `DisplayMonitor.swift` | `CGDisplayRegisterReconfigurationCallback`, event-driven. Reacts only to add/remove/enable/disable — mode, move, mirror and shape changes fire during Mission Control and fullscreen — via the tested free function `shouldReactToDisplayChange(_:)`, using the named `CGDisplayChangeSummaryFlags` constants, never raw hex; `.beginConfigurationFlag` is skipped since completion follows. 1s settle debounce; fires only when the external count actually changes. `externalDisplayCount()` filters `CGDisplayIsBuiltin`, `CGDisplayIsActive`, `!CGDisplayIsAsleep` — clamshell, standby, phantom hubs. Wake: `didWakeNotification`/`screensDidWakeNotification` re-check after 2s on a separate work item (`pendingWakeCheck`) so a CG callback cannot cancel it; like every other check it fires only when the external count changed — a wake with the same displays never touches the Dock (`wakeWithTheSameDisplaysChangesNothing`). **`activeSpaceDidChangeNotification` is not observed** — AppleScript Dock changes trigger it and loop. |
| `DockController.swift` | Applies via `NSAppleScript` → System Events, **one `tell` block per property** so one refusal cannot take the others down; never `killall Dock`. Diff-based: reads a fresh `UserDefaults(suiteName: "com.apple.dock")` and pushes only what differs, so frequent re-applies cost nothing. Reads back after 1s and records `DockApplyOutcome`. KVO on the same domain (`DockPrefsObserver`) reports System Settings edits via `onExternalConfigChanged`, debounced 0.5s; own changes are filtered by comparing to `lastAppliedConfig` with `approximatelyEquals`. Injectable `openDefaults`, `runScript`, delays. |
| `SmartDockService.swift` | Orchestrator: display state → profile → apply. Guards every path on `isEnabled`. `activeProfileConfig` is what the profile in force *asks for*; `currentConfig` is what the Dock holds after verification — controls read the first, displays the second. **`activeProfile` is the profile in force** — the displays select it, `applyProfile(_:)` overrides it until the next display change, wake or refresh. Everything that edits "the current profile" in place goes through `updateActiveProfile(_:)` (auto-hide toggle, position menu, System Settings edits via `handleExternalDockChange`, gated by `syncFromSystemEnabled`) — writing by `hasExternalDisplay` put built-in values into the external profile. `activeProfileDescription` is the one wording for every UI, including the override state. Reconciles `currentConfig` to the verified outcome on refusal, leaving the stored profile alone. Posts `smartDockStateDidChange` with `activeProfileKey` only on real change. |
| `URLCommand.swift` | Parses `smartdock://`. Rejects foreign schemes, unknown verbs and `switch` with no target rather than guessing. |
| `AppleScriptCommand.swift` | `DockProfile` — the two profiles, with `displayName` and `init(hasExternalDisplay:)`; also the `.sdef` enumeration, mapping four-character codes to `URLCommand`. `AppleScriptCommandTests` pins the codes to literals **and** greps the shipped `.sdef`. |
| `DockApplyOutcome.swift` | What an apply actually achieved. Only **requested** properties can be reported rejected. `refusalNotice` is the user-facing line; `summary` the log line. |
| `RateLimiter.swift` | Hotkey rate limit — a blocked attempt does not push the deadline out — and `ProfileSwitchAnnouncer` (notification cooldown, keyed on `DockProfile`, not the hardware); both take `now` so edges are testable. The announcer records a state only when a banner actually shows. |
| `PendingCommandQueue.swift` | Holds commands that arrive before launch finishes — a URL or Apple Event can *launch* the app. In Core so the launch-crash fix is tested. |
| `DiagnosticReport.swift` | Markdown snapshot for **Copy Diagnostic Info** — never anything identifying; a test fails if it appears. Prints the active profile and the displays as two lines, since an override makes them disagree. The profile line is an exhaustive switch over `DockProperty` — `showsRecents` went unreported for two releases while a hand-written list promised "every property". |
| `LogExport.swift` | `log show` invocation for **Export Logs**, home directory redacted. Absolute `/usr/bin/log` — zsh shadows it. |
| `Log.swift` | `Logger`, subsystem `com.smartdock.app`, categories `general`/`display`. Records at **notice** or above — `.info`/`.debug` are never persisted and invisible to `log show`. |

### App (`Sources/SmartDock/` executable, `Sources/SmartDockUI/` library)

| File | Responsibility |
|---|---|
| `App.swift` | `@main`, manual `NSApplication` run loop, no nibs. `performCommand` is the single entry for every external input, queueing until managers exist. First-launch-only Accessibility prompt; "Reset Permission" flow polls `AXIsProcessTrusted` and relaunches. `applicationShouldHandleReopen` opens Settings when the app is launched again from `/Applications`. |
| `StatusBarController.swift` | Menu bar icon + menu: profile items (checkmark on `activeProfile`), **Dock Position** submenu, Hide/Show Dock, Refresh. Every item that moves the Dock goes through `hotkeyManager.perform`; position edits the profile in force via `service.updateActiveProfile` since it has no command. `autoenablesItems = false` so `updateActionAvailability` can grey them while disabled. `updateMenuState` is the one list of state-driven items, called on state change and on every open. Shows `refusalNotice` under the status line. |
| `SettingsWindow.swift` | Four tabs: **Dock** (`DockTabView`), **General** (`GeneralTabView`), **Shortcuts** (built here), **About** (`AboutTabView`). Keeps what spans the window: tab switching, the draft rules (`isDirty`, `askAboutDraft`), the header icon, the window delegate. Only the Dock tab scrolls — `DockTabView` defines its height from the inside, the others end in `lessThanOrEqualTo`. Default 420×720, measured; resizable 380×500–600×900, ⌘0 resets. Leaving the Shortcuts tab cancels a recording in progress. |
| `HotkeyManager.swift` | Global + local `NSEvent` monitors; `HotkeyAction` enum; 0.3s rate limit; `isRecording` pauses dispatch. `toggleAutohide` uses `with(...)`. |
| `HotkeyRecorder.swift` | Captures a keystroke into a `HotkeyBinding`; pauses the manager while recording; Escape clears; a ⌘/⌥/⌃ modifier is required — Shift alone is rejected (`HotkeyBinding.hasRequiredModifier`). Display names come from `charactersIgnoringModifiers`, so any keyboard layout works. |
| `AppIntentsSupport.swift` | Four intents + `ShortcutDockProfile` (`AppEnum`), all routing into `performCommand`. `ShortcutCoverage` is a build-time tripwire on `URLCommand`. |
| `ScriptingSupport.swift` | `NSScriptCommand` subclasses bound by `@objc(SD…Command)` name. Reach `@MainActor` via `MainActor.assumeIsolated` — sound because Apple Events arrive on the main thread. Bad input sets `scriptErrorNumber`/`scriptErrorString` rather than guessing a profile. |
| `NotificationManager.swift` | `UNUserNotificationCenter` banners on a change of `activeProfile` (from `activeProfileKey`), 3s cooldown; `willPresent` returns `[.banner, .sound]` (required for LSUIElement apps); lazy authorisation, flag cleared on denial. |
| `AppUpdateWatcher.swift` / `AppRelauncher.swift` | FS watcher on the executable prompts a relaunch after a Homebrew upgrade; relauncher waits for PID exit (max 5s) then `open -n`, bundle path via env var so nothing is interpolated into the shell. |
| `OnboardingWindow.swift`, `LaunchAtLogin.swift`, `AccessibilityChecker.swift` | First-launch welcome; `SMAppService` wrapper; `AXIsProcessTrusted` with a first-launch-only prompt (ad-hoc signing resets the grant on every update). |

### Views (`Sources/SmartDockUI/Views/`)

Self-contained pieces; each owns its layout and actions, the host wires callbacks.
`UI.swift` (shared factories, `glassWindow` returns the view to build into),
`PositionIcon`/`PositionPicker` (cached thumbnails, `onSelectionChange` fires only on taps),
`AboutTabView`, `GeneralTabView` (app behaviour, owns the notification-permission observer),
`DockTabView` (profile picker, form, Use Current / Discard / Apply, refusal notice, Sync
from System, status — every intent goes to the host as a callback, nothing is applied
here), `DockProfileForm` (one control per `DockProperty` behind one `configuration` get/set;
`binding(for: DockProperty)` holds each field's load and store side by side, and its
exhaustive switch means a new `DockProperty` does not compile until the form has a control
for it — Dock tab height 600, measured; it was 552 before the two newest toggles),
`AccessibilityWarningView` (Shortcuts-tab banner + `tccutil reset` flow).

### Tests (`Tests/SmartDockTests/`)

Swift Testing, suites in parallel. `Mocks.swift` has `MockDisplayMonitor`
(`simulateDisplayChange`), `MockDockController`, `MockServiceDelegate`; `TestSupport.swift`
has `ScratchPreferences` (in-memory defaults — a real suite domain belongs to `cfprefsd` and
leaks), `expectClose(_:_:within:)` and `waitUntil(_:timeout:)`. `MockDockController` keeps
its `mockSystemConfig` in step with what it accepted and calls `onApplyVerified`, the way
the real controller does a second after an apply; until it did, no service test could see
what happens after the Dock refuses something, and a real toggle bug shipped under a green
suite. The UI suites build the real
objects (`@testable import SmartDockUI`): views are clicked with `performClick`, menu
items fired through `item.target?.perform(item.action!, with: item)`, key handlers fed
`NSEvent.keyEvent(...)`, windows shown for real (`_ = NSApplication.shared` first, so
`NSApp.activate` has an app). What the UI suites never do: register a login item,
prompt for Accessibility, open a URL, spawn `tccutil` or `open -n`, or touch
`UNUserNotificationCenter` — the last one aborts a process without a bundle, which is
why `NotificationManager` reaches it only through `NotificationPosting` and its tests
hand it a recorder. Each such suite gives its manager a private `NotificationCenter`:
the manager listens for any sender, and parallel suites would otherwise hear each
other's switches. Never touch `UserPreferences.shared` in a test. `DockController`
is tested as the real type with `openDefaults`/`runScript`/delays injected; `SmartDockService`
takes the mocks. A bare `DisplayMonitor()` or `DockController()` appears only in a few smoke
tests that assert ranges safe on any machine — do not add more. Anchor size assertions to
`pixelsToScale()`, not knife-edge floats. `#expect` wraps its argument in a
closure, so a `mutating` call goes into a named `let` first. `ShotTool` asserts nothing —
it draws `assets/settings.png` from the real window, and is `.enabled(if:)` on `SHOT_PATH`
so an ordinary run neither executes it nor writes a file. It lives in the bundle because
only the bundle can build the view hierarchy, and it exists because the picture it
replaced was shot by hand at 1.8.1 and still showed a three-tab window five versions
later. `screencapture` is not an option from here: it needs a Screen Recording grant.

## Code Style

`swift-format` is authoritative (`.swift-format`, `make format`/`lint`); reach it via
`xcrun swift-format`. Do not hand-align columns. Disabled rules and their reasons are in
`CONTRIBUTING.md`. Beyond the formatter:

- Names: `UpperCamelCase` types, `lowerCamelCase` everything else including constants;
  protocols `-ing`/`-able`; Bools read as assertions (`isEnabled`, `hasExternalDisplay`);
  abbreviations keep Apple's casing (`bundleID`, `displayIDs`, `repoURL`, `URLCommand`; `UI` alone).
  Delegate methods are prefixed with the subject (`serviceDidUpdateState`).
- `// MARK: -` sections; properties → init → public → private; protocol conformances in
  extensions at the bottom; related constraints and setup grouped in a dedicated
  `private func` (`buildUI`, `setupStatusItem`). One type per file, small related types allowed.
- `private` by default, `internal` never written out; `public` only for what the app target
  consumes; `final` on every class (only `NSObject` subclasses inherit). Helper extensions
  stay next to their use, `private` when single-file.
- `struct` and `let` unless there is a reason; caseless `enum` for namespaces; force
  unwraps only for AppKit objects set immediately after init; no `Any`/`AnyObject` outside
  Objective-C interop.
- `guard` + early return over nested `if let`; trailing closure for the last parameter;
  `[weak self]` + `guard let self` in escaping closures; `@discardableResult` over `_ =`;
  default parameters over overloads; `lazy var` for expensive one-time setup; functions
  under ~40 lines.
- `Bool` return for fire-and-forget success; `Log.error` at the point of failure.
- Protocol-first DI (`DockControlling` then `DockController`); `weak var delegate`;
  singletons only for app-wide state, never for testable services — every UI type takes
  `prefs: UserPreferences = .shared` in its `init` and never names `.shared` in a body;
  the split into `SmartDockUI` found seven that did, and none of them could be tested.
- A modal dialog is a function the type takes (`SettingsWindow.decideDraft`, defaulting
  to `askWithAlert`): `NSAlert.runModal` cannot be answered from a test — worse, it
  **hangs the suite**, which is how the Accessibility banner's failure alert was found.
- Every call that leaves the process — `UNUserNotificationCenter`, `SMAppService`,
  `Process`, `NSWorkspace.open`, `AXIsProcessTrustedWithOptions`, `tccutil`, `NSSavePanel`
  — is reached through a parameter whose default is the real thing (`NotificationPosting`,
  `LoginItemRegistering`, or a plain closure such as `runLogShow`/`presentSavePanel`). The
  app passes nothing and behaves as before; a test passes a recorder and never registers a
  login item, opens a browser or posts a banner.
- Interpolation over concatenation, except long multi-part log messages.

## Conventions

**Concurrency.** Every core and UI type is `@MainActor`; value types are `Sendable`;
`nonisolated(unsafe)` only for state `deinit` must read to tear down (a running flag, an event
monitor, a dispatch source, the observed `UserDefaults`), each with a comment saying so; no `Task.detached`
to escape isolation; closures crossing isolation are `@Sendable`.

**Profile in force vs. hardware.** `service.activeProfile`, never `hasExternalDisplay`,
is what the menu, the Settings picker, the banner and the diagnostic report mean by "the
current profile". `hasExternalDisplay` is only for saying what is plugged in.

**AppKit.** Programmatic Auto Layout, `NSLayoutConstraint.activate([...])`, no nibs.
`LSUIElement = true`; never call `setActivationPolicy(.accessory)` — it can drop the
status item at launch. Glass via `NSVisualEffectView` (`.hudWindow` / `.popover`).
The menu bar icon is drawn programmatically (`makeIcon`, cached per position and visibility)
with `isTemplate = true`; menu items and windows use SF Symbols directly, no fallback. Sliders show
the value in pixels — the unit System Settings uses. **Nothing in the Dock tab is applied
without Apply**: a draft survives a tab switch and a display change; switching profiles or
closing the window with a draft asks Apply / Discard / Cancel (`askAboutDraft`). Until
2.6.2 three paths applied silently and one discarded silently.

**Global hotkeys.** Recording and matching go through `HotkeyBinding` in Core —
`normalize` when storing, `matches(keyCode:modifiers:)` when dispatching, `displayString`
when showing — because
CapsLock/Fn ride along on key events and a binding recorded under one flag state would
silently stop firing under another. `HotkeyBindingTests` guards it.

**External commands.** Adding one touches four places: `URLCommand`, the `.sdef` plus its
`NSScriptCommand`, and an intent. Each is a tripwire: the exhaustive switches in
`HotkeyAction(URLCommand)`, `ShortcutCoverage` and `AppleScriptCommandTests` fail the build
until the hotkey, the intent and the `.sdef` command name are named; the test then checks
the dictionary declares it, and `sdef-check` that its `cocoa class` exists in
`ScriptingSupport.swift`. `show settings`, not `open settings` — `open` collides with the
Standard Suite. `make app` copies the `.sdef` into `Contents/Resources`; its filename
must match `OSAScriptingDefinition` in `Info.plist` exactly.

**App Intents.** `Metadata.appintents` is not produced by `swift build`; `make appintents`
rebuilds Xcode's phase from `swiftc -typecheck -emit-const-values` (undocumented driver
flag; output-file-map keys must be absolute) and `appintentsmetadataprocessor`
(`-const-gather-protocols-file` wants a bare array, hence `plutil -extract`). Extraction is
`-typecheck` only — a `-c` pass with an ignored file map drops object files into the repo root. **The
metadata ships only in a Developer ID build** — `linkd` refuses an ad-hoc bundle with
`Rejecting invalid client due to requiresValidatedBundle` (hardened runtime does not help),
so shipping it would list actions that always fail. `make app` builds and verifies it; only `make sign` copies it in.
Do not "fix" this in `app`. Point `release` at `sign` once a certificate exists.

**UserDefaults.** App keys under `com.smartdock.`. Read `com.apple.dock` through a fresh
`UserDefaults(suiteName:)` each time — the Dock process writes it and a cached instance
goes stale. `object(forKey:) != nil` to test presence.

**Logging.** `Log.info` / `Log.error` / `Log.displayChange`, never `print()`.

## Entitlements & Permissions

`com.apple.security.automation.apple-events` (System Events) and
`com.apple.security.scripting-targets` scoped to `com.apple.systemevents.dock.preferences`;
sandbox **off**; `LSUIElement = true`. Accessibility is needed only for global hotkeys —
Dock switching works without it.

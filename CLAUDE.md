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
the bundle, but a **SwiftUI** view cannot be clicked from a test and this package takes no
view-inspection dependency — so behaviour lives in an `@Observable` model (`Models/`) and
is tested there, with the view holding nothing to miss; logic still moves into Core when
it can. A test that waits for the main
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
`push(_:of:)`, `ShortcutCoverage.intentType(for:)`, `DockProfileFormContent.control(for:)`,
`store(_:of:forKey:)`/`restore(_:into:from:)` — and by a test or make target where it
cannot: `.sdef` parity, `anEditToEveryPropertyIsReported` (the KVO key list),
`everyPropertyIsReadFromItsSystemKey` (`readSystemConfig` — its initialiser defaults every
argument, so a property it forgets to read compiles and returns *our* value),
`everyDockPropertyIsPlacedInTheForm` (a setting drawn but never placed),
`theOtherTabsAreNotClipped` (a tab with no scroll view outgrowing the window),
`themenuIsBuiltInThisOrder` (the menu's whole running order, separators included),
`thesegmentsAreTheTabs` (the tab control against `Tab.allCases` **and** against the words),
`appintents-check`, `sdef-check`, `entitlements-check`, `version-check`.

**A list repeated in two places will drift.** `toggleAutohide` rebuilt the config field by
field and silently reset every setting it had not heard of; a `zip` against a literal list
quietly stopped checking two properties; the settings form read and wrote through two
separate lists until both directions of each field were put on one line — first in the
AppKit form's `binding(for: DockProperty)`, now in `DockProfileFormContent.bind(_:_:)`; `save`, `load`, `backfillMissingSettings` and `migrateMode`
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
make bump V=1.2.3 / version-check / release    # version everywhere (+ redraws the screenshot) · verify refs · build + zip + gh release
make shot                                      # redraw assets/settings.png at the current version
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

**The README screenshot carries the version**, drawn from `Bundle.main.shortVersion` into
the window header, so `bump` redraws it — `make shot` on its own does the same. It used to
be a separate thing to remember and went five releases stale. `bump` skips it when `CI` is
set: the release workflow bumps in a working copy it never commits, so a picture drawn
there is thrown away, and building the test bundle to draw it would add minutes to every
release and one more way for one to fail. Its appearance is pinned to light in `ShotTool`
rather than left to the machine — the same shot came out dark one evening and light the
next morning.

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
`codesign --verify --strict` — run over a **matrix of two toolchains**: `macos-26` with
Xcode 26.6, which gates the merge, and `xcode-27` with Xcode 27.1, which cannot
(`continue-on-error: ${{ matrix.preview }}`) and is there to compile the Swift 6.4 output
layout the release toolchain never produces. One `toolchain` field per entry drives both the
`xcode-select` path and the cache key, so those cannot drift. **The cache key had to be
split**: `runner.os` is `macOS` on both runners, so the single key that was there would hand
each entry the other's incompatible `.build` and produce a failure with nothing to do with
the commit. `fail-fast: false`, because the interesting moment is precisely the one where a
toolchain fails and the other does not. Lint runs first so a formatting PR fails in seconds.
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

**The release is arm64 only, and the cask says so.** `release.yml` builds on `macos-26`,
which is an Apple-silicon runner, and `lipo -archs` on the shipped binary reports `arm64`
alone — measured. The cask therefore carries `depends_on arch: :arm64`: without it Homebrew
installed happily on an Intel Mac and produced an app that would not open. The **formula**
deliberately has no such line, because it runs `swift build` from source and yields a native
binary wherever it runs; that is the Intel path, and the README says so. The `sed` lines that
rewrite the cask on release touch only `version` and `sha256` — checked by running them
against a copy — so the architecture line survives every release.

**A change to the tap is pushed before the tag, never after.** The 🍺 Homebrew job does
`git clone` of the tap and `sed`s the files **as they stand in its default branch** — it does
not know about work sitting in a local clone. 3.0.1 is the proof: the cask's `arch` guard and
the formula's Xcode floor were written, reviewed and verified, the tag went up first, the bot
cloned a tap that had never seen them, rewrote `version`/`sha256` and pushed — so the release
published a tap still installing on Intel, and the local clone was left three commits behind
with modifications to the very lines the bot had just changed. Nothing failed and nothing
warned; the release was green. Recovering it is not a merge: reset the local clone to origin,
re-apply the change on top of the new base, and check `version`/`sha256` did not travel
backwards with it. The order is the whole fix — **tap first, then the tag.**

**The formula's `depends_on xcode:` has to track `swift-tools-version`, and nothing can make
it.** It said `16.0` while the package declared tools `6.2`, which first shipped in Xcode 26:
Homebrew accepted the install and `swift build` then stopped partway through over tools
versions — the cask's Intel bug in a second costume, Homebrew taking on work it cannot finish.
It reads `26.0` now, and `brew info` confirms it as `Build: Xcode >= 26.0`. This is the one
agreement in the project that is **a note and not a tripwire**, said plainly rather than
implied: the two halves are in different repositories, so no exhaustive switch reaches it, and
a make target that compared them would read the developer's `brew` state — passing on CI, where
the tap is absent, and failing only locally, which is the CI-cannot-follow-the-dev-machine trap
one section down. Raising the tools version means editing the tap in the same breath.

**Downloads in the tap step are fetched with `curl -f`, into a file.** `curl -sL "$URL" |
shasum` was there, and on a 404 curl writes GitHub's 9-byte "Not Found" page to stdout and
exits **0** — measured against a missing asset, which hashes to
`0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5`. That hash would have gone
into the tap and broken `brew install` for everyone, and the pipe hid it twice over: the step
sets no `pipefail`. The `grep -qF` check below those lines does **not** catch this — it
confirms the computed sha reached the file, not that the sha is right. The `sleep 10` that
stood in for waiting is gone with the pipe: `--retry 10 --retry-delay 3 --retry-all-errors`
waits only as long as it must and fails loudly when the asset never arrives.

`release.yml` sets Xcode via `env.XCODE_PATH` at workflow level, never inline, which is
right there because all four of its jobs are `macos-26`. `ci.yml` has no such variable: with
two runners the **pairing** is the whole point, so each matrix entry carries its own
`toolchain` and there is no file-wide value that could name a runner and an Xcode which do
not belong together. Runner and Xcode must agree — check the
[runner image readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
before bumping either. Actions are pinned by major (except `webfactory/ssh-agent`, a 0.x release pinned exactly);
`make actions-check` compares to latest — never write the
numbers into this file, they go stale.

## Known Build Gotchas

**SPM's output layout moved.** Swift ≤6.3 writes modules to `.build/release/Modules/`;
Swift 6.4 (Xcode 27) builds through swift-build, `.build/release` becomes a **relative**
symlink to `out/Products/Release` — that is `.build/out/…`, inside the build directory and
not a sibling of it, measured by following the link and looking for a repo-root `out/`,
which does not exist. It is why `ci.yml` caching `path: .build` still covers the new layout.
The module is a bundle directory there, and the test bundle is
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

**CI follows the dev machine on one side only.** The release is still built by `macos-26`,
which stops at Xcode 26.6, so the toolchain that *ships* the app is not the one a developer
on Xcode 27 compiles with. What changed is that the other side is no longer unwitnessed:
there is no `macos-27` label, but an **`xcode-27`** image exists — macOS 27.0.1 carrying
Xcode 27.0, 27.1 and 27.2 beta, measured against the runner-images repository rather than
recalled — and `ci.yml`'s matrix pins an entry to **27.1**, the version this machine runs, so
every push now compiles the Swift 6.4 layout somewhere other than a developer's laptop. That
entry is `continue-on-error` because the image is marked **preview**, which its own
announcement defines as software that may be unstable with capacity still being balanced:
reason to watch a toolchain, not to gate a merge on it. Nothing in the release path moves
there until the preview label is gone. **A green local suite is still not proof, and now a
green workflow is not either** — a `continue-on-error` entry can sit red for a week while
every check reads as passing, so the matrix is worth looking at and not just the tick.

The gap is not theoretical. `make coverage` passed on Xcode 27 and failed to
compile on 26.6 over `let button = try #require(button("Export", in: view))`: inside a
`#require` expansion the older compiler resolves the call to the variable being declared
("cannot call value of non-function type"). **Never give a local the name of a function in
scope**, least of all inside a macro. Anything a test does that the compiler has opinions
about — macros, shadowing, inference — is verified by the next CI run, not by the local one.

**Invoking a `#require` result in place crashes swift-frontend.** `try #require(x.first)()`
— calling the macro's value straight away — segfaults the compiler rather than failing to
compile, and the only clue is which file it was type-checking. Name it first. Same family as
the shadowing trap above: inside a macro expansion the compiler has opinions, and a test that
exercises them is verified by building, never by reading.

**Handing a closure to SwiftUI as a *value* crashed IR generation on Xcode 26.6.**
`Binding(get: …, set: set)` where `set` is an `@escaping @MainActor (Bool) -> Void`
parameter: the compiler must reabstract the isolated function into a plain one, and the
thunk for it (`@$sSbScA_pSgIeAghyg_SbIeAghn_TR`) segfaulted swift-frontend on the toolchain
**CI builds with**, while Xcode 27 compiled it silently. Call it inside a new closure
instead — `set: { set($0) }` — which is the shape `DockProfileFormContent.bind` already
had and the reason that file survived the same build. The same goes for
`Button(action: someStoredClosure)`. This is the third entry in this section about the
dev machine and CI disagreeing, and the first one the **type checker** did not catch:
it got all the way to code generation.

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
**SmartDockUI** (the UI layer as a library: SwiftUI tabs over `@Observable` models, inside
AppKit windows and an AppKit menu bar) and **SmartDock** (the executable: `App.swift`, `AppIntentsSupport.swift`,
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
| `DockConfiguration.swift` | `DockConfiguration` value type: position, autohide, icon size (0.0–1.0 scale, `pixelsToScale`/`scaleToPixels`, 0.01 tolerance), magnification, `MinimizeEffect` genie/scale, `animatesLaunch`, `showsRecents`, `showsIndicators`, `minimizesToApplication`, `menuBarAutoHide` (absent-key defaults measured: indicators on, minimize-into-app off, menu bar In Full Screen Only). `MenuBarAutoHide` is the odd one out twice over: four positions rather than a flag, and **two** stores outside `com.apple.dock` — `AutoHideMenuBarOption` in `com.apple.controlcenter` is what the System Settings popup shows, `_HIHideMenuBar` in the global domain is what actually hides the menu bar, and macOS never reconciles them. Measured both ways: writing the option moved the popup and hid nothing; hiding through System Events left the popup reading its old position. `with(...)` copies with fields replaced — the guard against field-by-field rebuilds. `differences(from:)` is the apply diff, pure and tested. `UserPreferences` persists per-mode profiles plus flags and hotkeys, `prefs[profile]` by `DockProfile` — never `if external { externalConfig } else …` at a call site; `migrateIfNeeded` converts the pre-scale pixel keys and is called once from `applicationDidFinishLaunching`, not by `load`; `initializeDefaultsIfNeeded` makes both profiles the Dock as it is on a fresh install, so the first apply is a no-op; `backfillMissingSettings` fills keys an old profile predates from the live Dock. Every one of those four reaches a stored key through `storageKey(_:_:)` and a value through the exhaustive `store`/`restore` pair, so a property cannot be written without being read back or seeded; an absent key means *default* because `restore` returns the config untouched, never because a fallback was spelled out per field. `DockPosition`, `HotkeyBinding`. |
| `DisplayMonitor.swift` | `CGDisplayRegisterReconfigurationCallback`, event-driven. Reacts only to add/remove/enable/disable — mode, move, mirror and shape changes fire during Mission Control and fullscreen — via the tested free function `shouldReactToDisplayChange(_:)`, using the named `CGDisplayChangeSummaryFlags` constants, never raw hex; `.beginConfigurationFlag` is skipped since completion follows. 1s settle debounce; fires only when the external count actually changes. `externalDisplayCount()` filters `CGDisplayIsBuiltin`, `CGDisplayIsActive`, `!CGDisplayIsAsleep` — clamshell, standby, phantom hubs. Wake: `didWakeNotification`/`screensDidWakeNotification` re-check after 2s on a separate work item (`pendingWakeCheck`) so a CG callback cannot cancel it; like every other check it fires only when the external count changed — a wake with the same displays never touches the Dock (`wakeWithTheSameDisplaysChangesNothing`). **`activeSpaceDidChangeNotification` is not observed** — AppleScript Dock changes trigger it and loop. |
| `DockController.swift` | Applies via `NSAppleScript` → System Events, **one `tell` block per property** so one refusal cannot take the others down; never `killall Dock`. Diff-based: reads a fresh `UserDefaults(suiteName: "com.apple.dock")` and pushes only what differs, so frequent re-applies cost nothing. Reads back after 1s and records `DockApplyOutcome`. KVO on the same domain (`DockPrefsObserver`) reports System Settings edits via `onExternalConfigChanged`, debounced 0.5s; own changes are filtered by comparing to `lastAppliedConfig` with `approximatelyEquals`. **Three domains**: the menu bar's two halves live outside `com.apple.dock`, so there is a `DockPrefsObserver` over each — without them a position chosen in System Settings would be ignored and then pushed back by the next apply. `applyMenuBarAutoHide` writes both halves, and `apply` reapplies the position whenever they have fallen out of step, since a menu bar left hidden by one half produces no difference against a profile that agrees with the other. Both are reached through **one** `openDomain(_:)` seam keyed by domain name, not a closure each: two closures let a fixture supply the Dock's and forget the global one, then read the developer's real `NSGlobalDomain`. Injectable `openDomain`, `runScript`, delays. |
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
| `StatusBarController.swift` | Menu bar icon + menu: profile items (checkmark on `activeProfile`), **Dock Position** submenu, Hide/Show Dock, Refresh. Every item that moves the Dock goes through `hotkeyManager.perform`; position edits the profile in force via `service.updateActiveProfile` since it has no command. `autoenablesItems = false` so `updateActionAvailability` can grey them while disabled. `updateMenuState` is the one list of state-driven items, called on state change and on every open. Shows `refusalNotice` under the status line. The menu is built section by section — `addStatusSection`, `addServiceSection`, `addProfileSection`, `addWindowSection`, `addQuitItem` — where it used to be one 162-line function; `themenuIsBuiltInThisOrder` compares the whole running order, separators included, because swapping two sections broke nothing in the suite before it existed. |
| `SettingsWindow.swift` | The window around four SwiftUI tabs, each in an `NSHostingView`: **Dock** (`DockTabContent`), **General** (`GeneralTabContent`), **Shortcuts** (`ShortcutsTabContent`), **About** (`AboutTabContent`). Keeps what spans the window: tab switching, the draft rules (`isDirty`, `askAboutDraft`), the header icon, the window delegate, and the models the tabs read. Only the Dock tab scrolls, and now it has to — the native grouped form is 858pt against the window's 900pt maximum. The other three are pinned on **all four edges**: a hosting view left to its own `fittingSize` came up short of what SwiftUI drew and clipped the Shortcuts tab's last line, which with no scroll view was unreachable (`theOtherTabsAreNotClipped`). Default 420×**800** (750 until the profile picker became two tiles — a tile carries an icon and a name where a segment carried words). The tab needs 780; the extra 20 is deliberate, because the window sat at **2pt** of headroom before and the next control broke it. Resizable 380×500–600×900, ⌘0 resets. `windowDidBecomeKey` re-reads the Accessibility permission — it was read once per window, so the tab went on saying *Not allowed* over a grant given a moment earlier. Leaving the Shortcuts tab cancels a recording in progress. `isAccessibilityGranted` is a parameter: the answer differs between a developer's machine and a CI runner. Built in named pieces — `buildHeader`, `buildTabControl`, `buildTabs`, `activateLayout` — where it used to be one 151-line function; the three scroll-less tabs share **one** constraint loop rather than three copies of the same block, and the segment labels come from `Tab.allCases.map(\.title)` rather than a literal beside the enum (`thesegmentsAreTheTabs` pins both the words and the agreement). |
| `HotkeyManager.swift` | Global + local `NSEvent` monitors; `HotkeyAction` enum; 0.3s rate limit; `isRecording` pauses dispatch. `toggleAutohide` uses `with(...)`. Rebuilds the monitors when SmartDock itself comes forward, because `addGlobalMonitorForEvents` ignores an Accessibility grant given after the monitor exists — a silent failure, hotkeys that never start firing. The workspace notification centre is a parameter (`workspaceEvents`) for the same reason `NotificationManager` takes one: it is process-wide, so the handler could not be tested without every parallel suite hearing it, and it went untested for exactly that reason. Each fixture hands over a private centre. |
| `HotkeyRecorder.swift` | Captures a keystroke into a `HotkeyBinding`; pauses the manager while recording; Escape clears; a ⌘/⌥/⌃ modifier is required — Shift alone is rejected (`HotkeyBinding.hasRequiredModifier`). Display names come from `charactersIgnoringModifiers`, so any keyboard layout works. |
| `AppIntentsSupport.swift` | Four intents + `ShortcutDockProfile` (`AppEnum`), all routing into `performCommand`. `ShortcutCoverage` is a build-time tripwire on `URLCommand`. |
| `ScriptingSupport.swift` | `NSScriptCommand` subclasses bound by `@objc(SD…Command)` name. Reach `@MainActor` via `MainActor.assumeIsolated` — sound because Apple Events arrive on the main thread. Bad input sets `scriptErrorNumber`/`scriptErrorString` rather than guessing a profile. |
| `NotificationManager.swift` | `UNUserNotificationCenter` banners on a change of `activeProfile` (from `activeProfileKey`), 3s cooldown; `willPresent` returns `[.banner, .sound]` (required for LSUIElement apps); lazy authorisation, flag cleared on denial. |
| `AccessibilityGrantWatcher.swift` | The flow after **Grant Access…** relaunches: show the Shortcuts tab, **ask** (what puts SmartDock in the list — `AXIsProcessTrusted` only reads), open the pane, then wait 300×1s for the switch and relaunch. Every outward call and the delay are parameters, so the whole wait is driven from a test; it sat in `App.swift`, outside the test bundle, until the missing ask was found. |
| `AppUpdateWatcher.swift` / `AppRelauncher.swift` | FS watcher on the executable prompts a relaunch after a Homebrew upgrade; relauncher waits for PID exit (max 5s) then `open -n`, bundle path via env var so nothing is interpolated into the shell. |
| `OnboardingWindow.swift`, `LaunchAtLogin.swift`, `AccessibilityChecker.swift` | First-launch welcome; `SMAppService` wrapper; `AXIsProcessTrusted` with a first-launch-only prompt (ad-hoc signing resets the grant on every update). |

### Views & models (`Sources/SmartDockUI/`)

**Every tab is SwiftUI; the window around them is not.** `SettingsWindow` keeps the glass,
the header, the tabs and the draft rules, and puts each tab's contents in an
`NSHostingView`. The menu bar stays AppKit and always will — `NSStatusItem` has no SwiftUI
equivalent, and `MenuBarExtra` can carry neither an `attributedTitle` with an
`NSTextAttachment` nor a tab stop, which is what the whole icon story below rests on.

**Logic lives in a model, never in a view.** A SwiftUI view cannot be clicked from a test,
and this package takes no view-inspection dependency, so a view that held behaviour would
hold untested behaviour. `Models/` is where the behaviour is: `DockTabModel`,
`GeneralSettingsModel`, `ShortcutsModel`, `AccessibilityStatusModel`, `AboutModel`. Each is
`@Observable`, each reaches every outward call through a parameter, and each is tested
without building a view.

**Settings are read through explicit setters, not settable properties.** A write can be
refused — a login item macOS declines, a permission the person says no to — and what the
switch shows has to be what the system reports, not what was asked for. A settable
property would need a `didSet` that corrects itself, which is a write inside a write.

`DockProfileFormContent` keeps the tripwire the AppKit form had and adds one: `control(for:)`
switches **exhaustively** over `DockProperty` so a new setting does not compile until it is
drawn, and `layout` says where each one goes with `everyDockPropertyIsPlacedInTheForm` failing
if one is missing. What was **lost**: the AppKit form kept a `FieldBinding` per property that a
test could drive through real controls, proving each read and write touched the same property.
A SwiftUI `Binding` cannot be reached without a dependency, so what stands in its place is that
the two sides sit on one line inside `bind(_:_:)`. Say so rather than implying coverage.

`DockTabContent` is **one compact card**, laid out by hand. `.formStyle(.grouped)` is what
System Settings uses and was tried first: it measured 858pt against the window's 900pt maximum,
so the tab scrolled and Apply sat below the fold. A grouped form also draws each section as a
card, so wrapping it in another was a card inside a card — 190pt on its own. Hairlines between
the rows were tried too and taken out: a rule between every setting turned eleven of them into
a ledger. The promise that everything fits without scrolling is back, and
`theDockTabFitsTheDefaultWindowWithoutScrolling` keeps it.

**The profile picker is two tiles, not a segmented control, because it carries two independent
facts.** Which profile is being *edited* is the border and tint; which one the displays have put
*in force* is a **checkmark beside the name** — the mark this app already uses for it, since the
menu sets `state = .on` on the same profile and AppKit draws that as a checkmark. An "Active now"
line said the same thing in a second language and cost a third row the other tile had to leave
blank to stay level. Before either, the two facts shared one string — a ● glued in front of the
name — and a person editing Built-in while External applied could not tell at a glance. That is
the same confusion between `activeProfile` and `hasExternalDisplay` the Principles warn about,
drawn on screen. `DockTabModel.isActive(_:)` and `selectedMode` are separate for the same reason,
and `editingAprofileIsNotTheSameAsItBeingInForce` pins them apart.

**A hosting view is pinned on all four edges.** Left to its own `fittingSize` it came up short of
what SwiftUI drew and the Shortcuts tab's last line was clipped against a frame that ended above
it — with no scroll view there, that line was simply unreachable. `theOtherTabsAreNotClipped`
measures the realised frame, not `fittingSize`: the first version of that test compared
`fittingSize` against the window and passed while the clipping was plainly visible.

`UI.swift` is down to the glass window and a label; the control factories went with the controls.
`PositionIcon` survives because the window header still draws one.

### Tests (`Tests/SmartDockTests/`)

Swift Testing, suites in parallel. `Mocks.swift` has `MockDisplayMonitor`
(`simulateDisplayChange`), `MockDockController`, `MockServiceDelegate`; `TestSupport.swift`
has `ScratchPreferences` (in-memory defaults — a real suite domain belongs to `cfprefsd` and
leaks), `expectClose(_:_:within:)` and `waitUntil(_:timeout:)`. `MockDockController` keeps
its `mockSystemConfig` in step with what it accepted and calls `onApplyVerified`, the way
the real controller does a second after an apply; until it did, no service test could see
what happens after the Dock refuses something, and a real toggle bug shipped under a green
suite. The UI suites build the real
objects (`@testable import SmartDockUI`): the one control a test can still press is the
window's `NSSegmentedControl`, driven through `tabControl.target?.perform(…)` — nothing is
clicked with `performClick`, which this file promised for a while after the symbol had left
the codebase and while the paragraph above said a SwiftUI view cannot be clicked at all.
Menu items are fired through `item.target?.perform(item.action!, with: item)`, key handlers fed
`NSEvent.keyEvent(...)`, windows shown for real (`_ = NSApplication.shared` first, so
`NSApp.activate` has an app). What the UI suites never do: register a login item,
prompt for Accessibility, open a URL, spawn `tccutil` or `open -n`, or touch
`UNUserNotificationCenter` — and `notestReachesTheRealAccessibilityPrompt` now reads the
suite's own source to keep the first of those true, because the rule was written here and
broken anyway: `promptIfFirstLaunch` had a public wrapper with no seams, and the one test
that called it was kept clear of the system dialog only by the guard it was testing. A
mutation of that guard put the dialog on screen. There is one function with default
arguments now, so there is no second entry point to forget — the last one aborts a process without a bundle, which is
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
status item at launch. Glass via `NSVisualEffectView` with **`.windowBackground`**, never `.hudWindow`: a HUD
material is for small floating panels and forces a vibrant **dark** appearance whatever the
system is set to. AppKit controls survived that; SwiftUI draws a segmented control's selected
chip through the vibrancy and it washed out to white-on-white, leaving the chosen profile
unreadable.
The menu bar icon is drawn programmatically (`makeIcon`, cached per position and visibility)
with `isTemplate = true`; menu items and windows use SF Symbols directly, no fallback.
**macOS 26 draws no `NSMenuItem.image` in a status menu, so the icons live in the
title.** Every item had an image and every symbol resolved — measured — yet the menu drew
plain text, not even reserving the image column; a thirty-line status item that set nothing
but `image` behaved the same, so it is the OS, not the app. An `NSTextAttachment` in
`attributedTitle` **does** draw, and follows the highlight and the theme — but only while
the symbol image reaches it untouched. Drawing it into a uniform box first, which is how
the icons were first lined up, rasterises it: the template mask does not survive and the
glyph then keeps one colour while the row highlights and the system switches theme around
it. So each icon keeps its own proportions and a **tab stop** at `textColumn` does the
aligning. The settings item is left bare, title and all: macOS decorates the item it
recognises as the app's settings with a gear of its own — measured by removing ours and
watching one remain — so ours made two, and a spacer on top of the system's image column
pushed that row's words 40pt clear of the rest. `setTitle(_:symbol:on:)` is the only way an
item gets its words: a bare `item.title =` is a bug in two directions — it leaves the
existing `attributedTitle` untouched, so the menu goes on showing the **old** words with the
icon, while the property says something else. `NSMenuItem.wording` reads what is drawn for
exactly that reason, and is what tests assert on; `title` stopped being the wording. Sliders show
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
goes stale. `object(forKey:) != nil` to test presence. The global domain is
`".GlobalPreferences"` (`DockController.globalPreferencesDomain`), **never**
`UserDefaults.globalDomain`: that constant is `"NSGlobalDomain"`, which `defaults` takes on
the command line but `UserDefaults(suiteName:)` rejects, returning `nil` while macOS logs
"does not make sense and will not work". It shipped through a green suite — every test
injects a store, so a name that opens nothing looks healthy — and reported a hidden menu
bar as visible until a live run caught it. `theGlobalPreferencesDomainOpens` guards it now.
A domain that will not open is not the same as an absent key; say so with `Log.error`
rather than answering with a default. A test that builds a real `DockController` injects
`runScript` even when it only means to read: left at its default it is the real System
Events, and an `apply` then reconfigures the machine running the suite — which is exactly
what a read-only-looking fixture did until it was caught by a menu bar that would not stay
put between runs.

**Logging.** `Log.info` / `Log.error` / `Log.displayChange`, never `print()`.

## Entitlements & Permissions

`com.apple.security.automation.apple-events` (System Events) and
`com.apple.security.scripting-targets` scoped to `com.apple.systemevents.dock.preferences`;
sandbox **off**; `LSUIElement = true`. Accessibility is needed only for global hotkeys —
Dock switching works without it.

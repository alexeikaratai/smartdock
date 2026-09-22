# Contributing to SmartDock

Thanks for taking the time to help. This document covers what you need to build the
project, the conventions the codebase follows, and what CI will check on your PR.

## Getting set up

**Requirements**

| | Version | Why |
|---|---|---|
| macOS | 14.0+ (Sonoma) | Minimum deployment target |
| Xcode | 26+ | Swift 6.2 first shipped in Xcode 26; earlier versions cannot build the package |
| Swift | 6.2+ | The package declares `swift-tools-version: 6.2` |

SmartDock has **no external dependencies** — only Apple frameworks. There is no
`Package.resolved` to install, no `brew bundle`, nothing to fetch. Clone and build:

```bash
git clone https://github.com/alexeikaratai/smartdock.git
cd smartdock
make doctor   # verifies swift, xcode, swift-format, llvm-cov, codesign, gh, git
make run      # build + bundle + launch
```

If `make doctor` reports a missing tool, fix that before anything else — the other
targets assume the toolchain is complete.

## Everyday commands

```bash
make build      # swift build -c release
make test       # swift test (Swift Testing, in parallel)
make format     # rewrite sources with swift-format
make lint       # check formatting without writing — this is what CI gates on
make coverage   # run tests and print a per-file coverage table
make app        # build + icon + ad-hoc signed .app bundle
make logs       # stream live logs (subsystem com.smartdock.app)
```

`make help` lists everything.

## Before you open a PR

```bash
make format && make lint && make test && make app
```

That is the same sequence CI runs, in the same order. If it passes locally it should
pass on the runner.

## Code style

Formatting is **not a matter of taste here** — it is enforced. `.swift-format` at the
repo root is the single source of truth, and `make lint` fails the build on any
deviation. Run `make format` before committing and the question never comes up.

Two settings differ from swift-format's defaults, to match the existing codebase:
4-space indentation (default is 2) and a 120-column line limit (default is 100).

A handful of rules are switched **off** on purpose. Each one would otherwise fight a
deliberate decision:

| Rule | Why it is off |
|---|---|
| `NeverUseImplicitlyUnwrappedOptionals` | `AppDelegate` holds `HotkeyManager!` and `StatusBarController!`. AppKit guarantees `applicationDidFinishLaunching` builds them before anything can reach them. |
| `NeverForceUnwrap`, `NeverUseForceTry` | `NSStatusItem` / `NSMenuItem` setup force-unwraps by AppKit convention. |
| `NoAccessLevelOnExtensionDeclaration` | `public extension HotkeyBinding` groups the hotkey value logic as one unit; moving `public` onto each member buries that grouping. |
| `UseSynthesizedInitializer` | `DockConfiguration`'s hand-written init carries default values and documentation the memberwise init cannot express. |
| `FileScopedDeclarationPrivacy` | Would rewrite `fileprivate extension DockPosition` to `private`, changing visibility within the file. |

Naming, file organisation, access control and the AppKit/concurrency conventions the
project follows are documented in [CLAUDE.md](CLAUDE.md). It is written for an AI
assistant but is an accurate description of the house style — read it before a
substantial change.

## Architecture in one paragraph

Three targets. **`SmartDockCore`** holds logic with no UI: configuration values,
display monitoring, dock control, URL parsing, diagnostics. **`SmartDockUI`** is the
AppKit layer as a library — menu bar, windows, views, hotkeys, notifications — so the
test bundle can build a view and read it back. **`SmartDock`** is the executable and
holds only what must carry the app's own module name: `@main`, the App Intents (their
identifiers are module-qualified) and the `@objc` scripting command classes.
Dependencies flow one way: the app imports UI and Core, UI imports Core, never the
reverse. External dependencies are consumed through protocols (`DisplayMonitoring`,
`DockControlling`) so tests can inject mocks.

**Put logic in Core whenever you can**, and a view's state behind a value you can set
and read — `DockProfileForm.configuration` is the shape to copy.

## Testing

```bash
make test
swift test --filter startBeginsMonitoring
```

Tests are written with **Swift Testing** — `@Suite`, `@Test`, `#expect` — and run in
parallel. They did not always: `UserPreferences.shared` is a singleton, and suites that
reset it trampled each other. That was fixed by removing the shared state rather than
scheduling around it, so there is nothing left to serialize.

Conventions:

- `SmartDockService` takes mocks through the `DisplayMonitoring` / `DockControlling`
  protocols. `DockController` is tested as the real type with `openDefaults`,
  `runScript` and the delays injected — a bare `DockController()` would run AppleScript
  against your actual Dock, and a bare `DisplayMonitor()` talks to the window server;
  both appear only in a few smoke tests that assert ranges safe on any machine.
- Mocks live in `Tests/SmartDockTests/Mocks.swift`.
- Anything touching stored settings takes a `ScratchPreferences` — in-memory defaults,
  torn down with the test. Never `UserPreferences.shared`.
- Extract pure logic that the system would otherwise hide — CG flag filtering and
  `approximatelyEquals` are free functions precisely so they can be tested directly.
- Don't assert on floating-point knife edges. Size comparisons use a 0.01 tolerance;
  anchor assertions to `pixelsToScale()` values rather than hand-written decimals.

### About the coverage numbers

`make coverage` reports on `SmartDockCore` and `SmartDockUI`. The `SmartDock`
executable — three files — is outside the test bundle and absent from the table.

Read the two halves differently. Core sits above 99% and every reachable branch has a
test. UI is around 90%, and what is left is the body of each system call — the step
that actually leaves the process. Every one of them is reached through a parameter
whose default is the real thing, so the decisions around the call are tested and only
the call is not: `UNUserNotificationCenter` behind `NotificationPosting` (its
`current()` aborts any process without a bundle — measured, "bundleProxyForCurrentProcess
is nil"), `SMAppService` behind `LoginItemRegistering`, and plain function parameters
for `runLogShow` (`log show` in a subprocess), `presentSavePanel`, spawning the relaunch
shell, prompting for Accessibility, opening a URL, running `tccutil`, and every
`NSAlert`. Two exceptions are tested for real because they are harmless: `spawn` with a
plan that runs `/usr/bin/true`, and the file-system source, by writing to a temporary
file it watches. A modal alert does not merely go untested: it hangs the whole suite
until it is seamed, which is how the failure alert in the Accessibility banner was
found. Logic still belongs in Core when it can go there. `HotkeyBinding` is the worked example —
modifier normalisation and matching started in the app layer, where a silent divergence
between recording and dispatching was untestable, and moved to Core so
`HotkeyBindingTests` could pin the behaviour down.

`NSStatusBar`, `NSWindow`, `NSPasteboard` and synthetic `NSEvent`s all work in the test
process (measured), so a menu, a window or a keystroke is tested for real rather than
through a mock. Don't write tests that only assert a mock was called. A test that waits
for something to *arrive* on the main queue waits for it (`waitUntil`), never for a fixed
time — the view tests keep the main thread busy, and a fixed sleep became a coin toss the
day they appeared.

A handful of "missed regions" in the table are not misses at all. A ternary or a `??`
inside a string interpolation — `"\(flag ? "on" : "off")"`, `"\(dict[key] ?? "unknown")"`
— gets a counter from `llvm-cov` that Swift never increments, so the fallback reads as
unexecuted even with a passing test that asserts on it. `DiagnosticReport.formatted`
carries four of these and `DockController.executeAppleScript` one. Check the region
marker against the test before chasing it.

What is left after that is deliberate: the three guards in `DisplayMonitor` for a
CoreGraphics call failing (`CGGetActiveDisplayList`, an inactive or asleep display,
`CGDisplayRegisterReconfigurationCallback`). Covering them would mean wrapping three
more system calls in injectable closures for tests that assert "on failure, return 0".
Every other branch in Core has a test, including the `guard let self` in each deferred
work item — there is a test per class that releases the object mid-debounce.

## Versioning

**Never edit a version by hand.**

```bash
make bump V=1.2.3
```

The version appears in four places — `Makefile`, two keys in `Resources/Info.plist`,
and the README badge (URL *and* alt text). `make bump` is the only thing that knows all
of them, and it finishes by running `make version-check`, which fails loudly if any
reference is stale. CI runs `version-check` on every push, and `release.yml` calls
`make bump` rather than re-implementing the substitutions.

If you add a fifth place the version is written, add it to both the `bump` and
`version-check` targets.

## Commits and pull requests

- Branch from `dev` for features; `main` is the release branch.
- Write commit subjects in the imperative mood: "Add position picker", not "Added" or
  "Adds".
- Keep formatting-only changes in their own commit. A PR that mixes a `make format`
  sweep with a behaviour change is very hard to review.
- Fill in the PR template. The checklist is short and it is there because each item has
  broken a release at least once.

## Reporting bugs

Open a [bug report](https://github.com/alexeikaratai/smartdock/issues/new?template=bug_report.yml)
and include the output of **Settings → About → Copy Diagnostic Info**. It captures
versions, permission state, display count and both dock profiles, and deliberately
contains nothing identifying — no username, no paths, no serial numbers. There is a
test that fails if identifying data ever creeps in.

For anything involving hotkeys, check Accessibility first: ad-hoc signing changes the
binary's CDHash on every rebuild, which makes macOS silently revoke the grant.
**Settings → Shortcuts → Reset Permission** walks through re-granting it.

## License

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE).

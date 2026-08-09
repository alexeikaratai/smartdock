## What changed

<!-- One or two sentences. What does this PR do, and why? -->

## Why

<!-- The problem being solved. Link the issue if there is one: Fixes #123 -->

## How to verify

<!-- Steps a reviewer can follow. For UI changes, a screenshot or short clip helps.
     For display-switching changes, say which monitor setup you tested on —
     that behaviour cannot be verified in CI. -->

---

## Checklist

```bash
make format && make lint && make test && make app
```

- [ ] `make lint` passes — formatting is enforced, not advisory
- [ ] `make test` passes (121+ tests, run sequentially)
- [ ] `make app` succeeds — this is the only thing that exercises icon generation,
      entitlements and ad-hoc signing
- [ ] New logic that *could* live in `SmartDockCore` does, and is covered by tests
- [ ] Version was **not** edited by hand — use `make bump V=x.y.z` if it needed changing
- [ ] `CHANGELOG.md` updated under `## [Unreleased]` for anything user-visible
- [ ] `CLAUDE.md` / `README.md` updated if this changes architecture, commands or behaviour

### If this PR touches CI or the toolchain

- [ ] The `runs-on:` runner and `XCODE_PATH` still agree — check the
      [runner image readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
      for which Xcode versions are actually installed
- [ ] `swift-tools-version` in `Package.swift` is supported by the Swift version on that runner

> Both of these have broken `main` before. A version that exists on your Mac is not
> evidence it exists on the runner.

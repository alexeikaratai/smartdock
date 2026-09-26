.PHONY: help build test clean icon app run sign notarize fix install release bump version-check changelog-check release-notes deps outdated doctor actions-check logs format lint coverage appintents appintents-check entitlements-check sdef-check

.DEFAULT_GOAL := help

# === Config ===
APP_NAME     := SmartDock
BUNDLE_ID    := com.smartdock.app
VERSION      := 2.8.4
BUILD_DIR    := .build/release
APP_DIR      := build/$(APP_NAME).app
CONTENTS     := $(APP_DIR)/Contents
MACOS_DIR    := $(CONTENTS)/MacOS
RESOURCES    := $(CONTENTS)/Resources
TEAM_ID      ?= YOUR_TEAM_ID
SIGN_ID      ?= Developer ID Application: Your Name ($(TEAM_ID))

# === Build ===

build:
	@echo "🔨 Building $(APP_NAME)..."
	swift build -c release

test:
	@echo "🧪 Running tests..."
	swift test

# === Formatting & Linting ===
# swift-format ships inside the Xcode toolchain — reached via xcrun, never a bare
# `swift-format` (not on PATH) and never `swift format` (absent before Swift 6.2).
# Rules live in .swift-format; `lint` is what CI gates on, `format` is the fixer.

SWIFT_FORMAT := xcrun swift-format
SWIFT_SOURCES := Sources Tests

format:
	@echo "🎨 Formatting Swift sources..."
	@$(SWIFT_FORMAT) format --in-place --recursive $(SWIFT_SOURCES)
	@echo "✅ Formatted"

lint:
	@echo "🔎 Linting Swift sources..."
	@$(SWIFT_FORMAT) lint --strict --recursive $(SWIFT_SOURCES) && \
		echo "✅ No violations" || \
		{ echo "❌ Formatting violations — run: make format"; exit 1; }

# === Coverage ===
# Prints a per-file table for SmartDockCore. The SmartDock target is an executable
# and is not linked into the test bundle, so it never appears here — that gap is
# intentional and documented in CONTRIBUTING.md.
#
# The test bundle is located, not named: up to Swift 6.3 SPM calls it
# SmartDockPackageTests.xctest after the package, from Swift 6.4 (swift-build)
# SmartDockTests.xctest after the test target. The binary inside always carries the
# bundle's own name, so deriving it from whatever *.xctest is present serves both.

coverage:
	@echo "🧪 Running tests with coverage..."
	@swift test --enable-code-coverage
	@echo ""
	@set -e; \
	bin=$$(swift build --show-bin-path); \
	prof=$$(swift test --show-codecov-path); \
	bundle=$$(ls -d "$$bin"/*.xctest 2>/dev/null | head -1); \
	if [ -z "$$bundle" ]; then \
		echo "❌ No .xctest bundle in $$bin — did the test build change layout again?"; \
		exit 1; \
	fi; \
	binary="$$bundle/Contents/MacOS/$$(basename "$$bundle" .xctest)"; \
	xcrun llvm-cov report \
		"$$binary" \
		-instr-profile="$$(dirname $$prof)/default.profdata" \
		-ignore-filename-regex='.build|Tests/'

# === App Intents Metadata ===
# Xcode generates Metadata.appintents in an ExtractAppIntentsMetadata build phase.
# SPM has no equivalent, and without that bundle the intents compile, link, and do
# nothing at all — Shortcuts.app and Spotlight read it, and only it, to discover
# what the app can do. So the phase is rebuilt here from the two tools that ship
# inside Xcode:
#
#   1. swiftc -typecheck -emit-const-values  ->  one .swiftconstvalues per source
#   2. appintentsmetadataprocessor           ->  Metadata.appintents
#
# The bundle is generated on every build but reaches the .app only in `sign` —
# macOS refuses the intent connection to a bundle it cannot validate, so shipping
# the metadata in an ad-hoc build advertises actions that can never run. Building
# it here regardless keeps the pipeline and `appintents-check` exercised in CI, so
# it cannot rot while waiting for a signing certificate.
#
# Extraction is typecheck-only: it writes no object files and nothing outside
# .build, so it neither disturbs `swift build` nor can be replaced by it.
# `-emit-const-values` and `-const-gather-protocols-file` are both undocumented,
# which is exactly why `appintents-check` runs afterwards — a toolchain that drops
# them fails the build instead of shipping an app whose Shortcuts actions silently
# disappeared.
#
# The two -enable-upcoming-feature flags must match `upcomingFeatures` in
# Package.swift; adding one there and not here fails this step loudly.
#
# Two module search paths, because SPM moved its output between toolchains: up to
# Swift 6.3 the module sits at .build/release/Modules/SmartDockCore.swiftmodule;
# from Swift 6.4 SPM builds through swift-build, .build/release becomes a symlink to
# out/Products/Release and the module is an Xcode-style bundle directory right
# there. A missing -I directory is harmless, so both are always passed. Found the
# day Xcode 27 landed: swiftc failed with "no such module", but the recipe chained
# its commands with `;`, so the processor ran anyway and reported twelve missing
# files instead of the one real cause. The recipe now runs under `set -e`.
#
# Two details that are easy to get wrong and silently produce an empty bundle:
#   - The toolchain ships the protocol list as {version, constValueProtocols} but
#     the compiler wants the bare array, hence `plutil -extract`. Reading the
#     toolchain copy rather than pinning our own means a future Xcode that adds a
#     protocol is picked up for free.
#   - Const values are emitted per source file, so the driver needs an output file
#     map naming each one. Its keys must be absolute paths that match exactly what
#     swiftc is handed, or the map is ignored without a word of warning.

APPINTENTS_DIR  := .build/appintents
APPINTENTS_CV   := $(APPINTENTS_DIR)/const-values
APPINTENTS_META := $(APPINTENTS_DIR)/Metadata.appintents
APPINTENTS_SRC  := Sources/$(APP_NAME)/AppIntentsSupport.swift

# Prints the body of `## [VERSION]` from the CHANGELOG, stopping at the next heading.
# On one line, with every `#` escaped: in a variable assignment make treats `#` as the
# start of a comment (a recipe line does not), and a continuation lands inside the awk
# program. Both truncate it to `awk -v v='` and the shell reports an unmatched quote.
CHANGELOG_SECTION = awk -v v='\#\# [$(VERSION)]' 'index($$0, v) == 1 { f = 1; next } /^\#\# \[/ { f = 0 } f' CHANGELOG.md
ENTITLEMENTS    := Resources/$(APP_NAME).entitlements
SDEF            := Resources/$(APP_NAME).sdef
SCRIPTING_SRC   := Sources/$(APP_NAME)/ScriptingSupport.swift
DEPLOY_TARGET   := 14.0

appintents: build
	@echo "🧩 Extracting App Intents metadata..."
	@rm -rf $(APPINTENTS_DIR)
	@mkdir -p $(APPINTENTS_CV)
	@set -e; \
	toolchain=$$(xcrun --find swiftc | sed 's|/usr/bin/swiftc$$||'); \
	sdk=$$(xcrun --show-sdk-path --sdk macosx); \
	triple=$$(uname -m)-apple-macos$(DEPLOY_TARGET); \
	cv=$(CURDIR)/$(APPINTENTS_CV); \
	plutil -extract constValueProtocols json -o $(APPINTENTS_DIR)/protocols.json \
		"$$toolchain/usr/share/swift/SwiftConstantValues/AppIntents.json"; \
	find $(CURDIR)/Sources/$(APP_NAME) -name '*.swift' | sort > $(APPINTENTS_DIR)/sources.txt; \
	awk -v dir="$$cv" \
		'{ n=$$0; sub(/.*\//,"",n); sub(/\.swift$$/,"",n); \
		   printf "%s\"%s\":{\"const-values\":\"%s/%s.swiftconstvalues\"}", (NR>1?",":"{"), $$0, dir, n } \
		 END { print "}" }' \
		$(APPINTENTS_DIR)/sources.txt > $(APPINTENTS_DIR)/output-file-map.json; \
	awk -v dir="$$cv" \
		'{ n=$$0; sub(/.*\//,"",n); sub(/\.swift$$/,"",n); print dir "/" n ".swiftconstvalues" }' \
		$(APPINTENTS_DIR)/sources.txt > $(APPINTENTS_DIR)/const-values.txt; \
	swiftc -typecheck -emit-const-values $$(cat $(APPINTENTS_DIR)/sources.txt) \
		-module-name $(APP_NAME) -swift-version 6 \
		-enable-upcoming-feature ExistentialAny \
		-enable-upcoming-feature MemberImportVisibility \
		-target "$$triple" -sdk "$$sdk" -I $(BUILD_DIR)/Modules -I $(BUILD_DIR) \
		-output-file-map $(APPINTENTS_DIR)/output-file-map.json \
		-Xfrontend -const-gather-protocols-file \
		-Xfrontend $(CURDIR)/$(APPINTENTS_DIR)/protocols.json; \
	"$$toolchain/usr/bin/appintentsmetadataprocessor" \
		--output $(APPINTENTS_DIR) \
		--toolchain-dir "$$toolchain" \
		--module-name $(APP_NAME) \
		--sdk-root "$$sdk" \
		--xcode-version "$$(xcodebuild -version | tail -1 | awk '{print $$NF}')" \
		--platform-family macOS \
		--deployment-target $(DEPLOY_TARGET) \
		--target-triple "$$triple" \
		--source-file-list $(APPINTENTS_DIR)/sources.txt \
		--swift-const-vals-list $(APPINTENTS_DIR)/const-values.txt \
		--force --quiet-warnings
	@$(MAKE) --no-print-directory appintents-check

# Verify the generated metadata against the source of truth: every intent declared
# in AppIntentsSupport.swift must appear in the bundle. Catches both a processor
# that silently produced nothing and an intent the extraction failed to see.
appintents-check:
	@echo "🔎 App Intents metadata:"
	@data=$(APPINTENTS_META)/extract.actionsdata; \
	if [ ! -f "$$data" ]; then \
		echo "  ❌ Metadata.appintents was not generated"; exit 1; \
	fi; \
	intents=$$(grep -oE '^struct [A-Za-z]+Intent: AppIntent' $(APPINTENTS_SRC) \
		| awk '{print $$2}' | tr -d ':'); \
	if [ -z "$$intents" ]; then \
		echo "  ❌ No intents found in $(APPINTENTS_SRC)"; exit 1; \
	fi; \
	fail=0; \
	for intent in $$intents; do \
		if grep -q "\"$$intent\"" "$$data"; then \
			printf "  ✅ %s\n" "$$intent"; \
		else \
			printf "  ❌ %s missing from metadata\n" "$$intent"; \
			fail=1; \
		fi; \
	done; \
	shortcuts=$$(grep -c 'AppShortcut(' $(APPINTENTS_SRC)); \
	if grep -q '"autoShortcuts":\[\]' "$$data" || ! grep -q 'phraseTemplates' "$$data"; then \
		printf "  ❌ %s App Shortcuts declared but none reached Spotlight\n" "$$shortcuts"; \
		fail=1; \
	else \
		printf "  ✅ %s App Shortcut(s) with Spotlight phrases\n" "$$shortcuts"; \
	fi; \
	if [ $$fail -eq 1 ]; then \
		echo "❌ App Intents metadata is incomplete"; \
		exit 1; \
	fi

# === Bundle checks ===

# Read the entitlements back out of the sealed bundle and compare them with the
# file they were signed from. `codesign` accepts any key it is given, so a typo
# or a dropped key is invisible until System Events refuses the app — and
# without `automation.apple-events` the app cannot change the Dock at all.
# Comparing against the file rather than a list of keys means the target never
# has to learn a new entitlement; the one key asserted by name is the one the
# app cannot work without, so an empty file on both sides cannot pass.
entitlements-check:
	@echo "🔎 Entitlements in $(APP_DIR):"
	@actual=build/entitlements.actual; expected=build/entitlements.expected; \
	codesign -d --entitlements :- $(APP_DIR) 2>/dev/null | plutil -p - > $$actual 2>/dev/null; \
	plutil -p $(ENTITLEMENTS) > $$expected; \
	if [ ! -s $$actual ]; then \
		echo "  ❌ codesign returned no entitlements — is the bundle signed?"; exit 1; \
	fi; \
	if ! diff $$expected $$actual > build/entitlements.diff; then \
		echo "  ❌ Bundle entitlements differ from $(ENTITLEMENTS) (< file, > bundle):"; \
		sed 's/^/     /' build/entitlements.diff; \
		exit 1; \
	fi; \
	if ! grep -q '"com.apple.security.automation.apple-events" => true' $$actual; then \
		echo "  ❌ com.apple.security.automation.apple-events is not granted — System Events would refuse the app"; \
		exit 1; \
	fi; \
	echo "  ✅ match $(ENTITLEMENTS)"

# Every <cocoa class> the scripting dictionary names must be an @objc class in
# ScriptingSupport.swift, and every such class must be in the dictionary. The
# two are hand-written in different languages and the compiler sees neither
# side; a mismatch fails at runtime with "unrecognised command". The Core test
# suite covers the enumerator codes and the URLCommand ↔ command mapping; the
# class names live in the app target, which is why this is a make target.
sdef-check:
	@echo "🔎 Scripting dictionary classes:"
	@mkdir -p build; declared=build/sdef.declared; defined=build/sdef.defined; \
	grep -oE 'cocoa class="[A-Za-z]+"' $(SDEF) | sed -E 's/.*"(.*)"/\1/' | sort > $$declared; \
	grep -oE '@objc\(SD[A-Za-z]+Command\)' $(SCRIPTING_SRC) | sed -E 's/@objc\((.*)\)/\1/' | sort > $$defined; \
	if [ ! -s $$declared ]; then echo "  ❌ $(SDEF) declares no <cocoa class>"; exit 1; fi; \
	if ! diff $$declared $$defined > build/sdef.diff; then \
		echo "  ❌ $(SDEF) and $(SCRIPTING_SRC) disagree:"; \
		sed -n 's/^< /     only in .sdef:  /p; s/^> /     only in Swift:  /p' build/sdef.diff; \
		exit 1; \
	fi; \
	sed 's/^/  ✅ /' $$declared

# === App Bundle ===

icon:
	@echo "🎨 Generating app icon..."
	cd $(CURDIR) && swift scripts/generate-icon.swift

app: build icon appintents
	@echo "📦 Creating $(APP_NAME).app bundle..."
	@rm -rf $(APP_DIR)
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES)

	@# Executable
	cp $(BUILD_DIR)/$(APP_NAME) $(MACOS_DIR)/$(APP_NAME)

	@# Resources
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	@# Scripting dictionary — the path in Info.plist's OSAScriptingDefinition is
	@# resolved relative to Contents/Resources, so the name must not change.
	cp Resources/$(APP_NAME).sdef $(RESOURCES)/$(APP_NAME).sdef
	@# App Intents metadata is deliberately NOT copied here — see `sign`.
	@# An ad-hoc signed bundle is rejected by Gatekeeper and has no Team ID, and
	@# `linkd` refuses the intent connection from such a process outright:
	@#   Rejecting invalid client due to requiresValidatedBundle
	@# The actions would still be listed in Spotlight and Shortcuts, and every one
	@# of them would fail with "couldn't communicate with the app" — worse for a
	@# user than not offering them at all. So they ship only with a real signature.
	@if [ -f Resources/AppIcon.icns ]; then \
		cp Resources/AppIcon.icns $(RESOURCES)/AppIcon.icns; \
	fi

	@# Ad-hoc sign (free, no Developer ID needed)
	@# Required for macOS to allow opening the app
	codesign --force --deep \
		--entitlements $(ENTITLEMENTS) \
		--sign - \
		$(APP_DIR)
	@$(MAKE) --no-print-directory entitlements-check
	@$(MAKE) --no-print-directory sdef-check

	@echo "✅ $(APP_DIR) created (ad-hoc signed)"
	@echo "   Run: open $(APP_DIR)"
	@echo "   ℹ️  Shortcuts/Spotlight actions omitted — they need a Developer ID (make sign)"

# === Run ===

run: app
	@echo "🚀 Launching $(APP_NAME)..."
	open $(APP_DIR)

# === Code Signing (for distribution) ===

sign: app
	@echo "🔐 Signing with: $(SIGN_ID)"
	@# The App Intents metadata joins the bundle here and nowhere else. Shortcuts
	@# and Spotlight discover the actions from it, but macOS only opens the intent
	@# connection to a bundle it can validate — so the metadata is meaningful only
	@# in a Developer ID build, and must be in place before codesign seals it.
	cp -R $(APPINTENTS_META) $(RESOURCES)/Metadata.appintents
	codesign --force --deep --timestamp \
		--options runtime \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGN_ID)" \
		$(APP_DIR)
	@echo "✅ Signed. Verify:"
	codesign --verify --verbose $(APP_DIR)
	@$(MAKE) --no-print-directory entitlements-check
	@# A signed build that Gatekeeper still rejects would list the actions and fail
	@# every one of them, so say so plainly rather than let it ship quietly.
	@if spctl -a -vv $(APP_DIR) >/dev/null 2>&1; then \
		echo "✅ Gatekeeper accepts the bundle — Shortcuts actions will work"; \
	else \
		echo "⚠️  Gatekeeper rejects the bundle — Shortcuts actions will NOT work"; \
		echo "    (notarize it: make notarize)"; \
	fi

# === Notarization (for distribution outside App Store) ===

dmg: sign
	@echo "💿 Creating DMG..."
	@mkdir -p build/dmg
	@cp -R $(APP_DIR) build/dmg/
	@ln -sf /Applications build/dmg/Applications
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder build/dmg \
		-ov -format UDZO \
		build/$(APP_NAME)-$(VERSION).dmg
	@rm -rf build/dmg
	@echo "✅ build/$(APP_NAME)-$(VERSION).dmg"

notarize: dmg
	@echo "📤 Submitting for notarization..."
	xcrun notarytool submit \
		build/$(APP_NAME)-$(VERSION).dmg \
		--team-id $(TEAM_ID) \
		--wait
	@echo "📌 Stapling notarization ticket..."
	xcrun stapler staple build/$(APP_NAME)-$(VERSION).dmg
	@echo "✅ Notarized and stapled"

# === Version Bump ===
# Usage: make bump V=1.2.3
#
# Single entry point for changing the version. Updates every place it is written:
#   Makefile            VERSION := x.y.z          (source of truth)
#   Info.plist          CFBundleShortVersionString + CFBundleVersion (build, +1)
#   README.md           shields.io badge URL + its alt text
#   CHANGELOG.md        opens a dated section for the version under [Unreleased]
# Then runs version-check so a missed spot fails loudly instead of shipping stale.
# CI calls this target too — do not duplicate the sed logic in workflows.

bump:
ifndef V
	$(error Usage: make bump V=1.2.3)
endif
	@echo "📌 Bumping version to $(V)..."
	@# Makefile — source of truth
	sed -i '' 's/^VERSION      := .*/VERSION      := $(V)/' Makefile
	@# Info.plist — short version string
	sed -i '' '/CFBundleShortVersionString/{n;s|<string>.*</string>|<string>$(V)</string>|;}' Resources/Info.plist
	@# Info.plist — build number, monotonically incremented
	@BUILD=$$(sed -n '/CFBundleVersion/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' Resources/Info.plist) && \
		NEW_BUILD=$$(( $$BUILD + 1 )) && \
		sed -i '' "/CFBundleVersion/{n;s|<string>.*</string>|<string>$$NEW_BUILD</string>|;}" Resources/Info.plist
	@# README — badge URL and alt text both carry the version
	sed -i '' -e 's|badge/version-[0-9][0-9.]*-|badge/version-$(V)-|' \
	          -e 's|alt="Version [0-9][0-9.]*"|alt="Version $(V)"|' README.md
	@# CHANGELOG — open a dated section for this version directly under [Unreleased],
	@# so whatever accumulated there becomes the release notes. Skipped when the
	@# section already exists, which makes re-running bump harmless.
	@if ! grep -q '^## \[$(V)\]' CHANGELOG.md; then \
		awk -v ver='$(V)' -v today="$$(date +%Y-%m-%d)" \
			'{ print } /^## \[Unreleased\]$$/ { print ""; print "## [" ver "] — " today }' \
			CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md; \
		echo "  📝 CHANGELOG: opened section [$(V)]"; \
	fi
	@$(MAKE) --no-print-directory version-check
	@echo "✅ Version: $(V), Build: $$(sed -n '/CFBundleVersion/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' Resources/Info.plist)"

# Verify every version reference matches the Makefile's VERSION.
# Run standalone at any time; `bump` runs it automatically.
version-check:
	@echo "🔎 Version references (expected $(VERSION)):"
	@plist=$$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' Resources/Info.plist); \
	badge=$$(sed -n 's|.*badge/version-\([0-9][0-9.]*\)-.*|\1|p' README.md | head -1); \
	alt=$$(sed -n 's|.*alt="Version \([0-9][0-9.]*\)".*|\1|p' README.md | head -1); \
	changelog=$$(sed -n 's|^## \[\([0-9][0-9.]*\)\].*|\1|p' CHANGELOG.md | head -1); \
	fail=0; \
	for entry in "Info.plist:$$plist" "README badge:$$badge" "README alt:$$alt" "CHANGELOG:$$changelog"; do \
		name="$${entry%%:*}"; value="$${entry##*:}"; \
		if [ "$$value" = "$(VERSION)" ]; then \
			printf "  ✅ %-14s %s\n" "$$name" "$$value"; \
		else \
			printf "  ❌ %-14s %s\n" "$$name" "$${value:-<not found>}"; \
			fail=1; \
		fi; \
	done; \
	if [ $$fail -eq 1 ]; then \
		echo "❌ Version mismatch — run: make bump V=$(VERSION)"; \
		exit 1; \
	fi
	@# The checks above compare the *topmost* CHANGELOG section, which says nothing
	@# about the ones beneath it. `bump` opens a dated section and stays silent if it
	@# is never filled, so bumping several times in a day leaves a trail of empty
	@# sections — and 2.5.0 shipped with its notes filed under a version that never
	@# existed. These two catch that: a version can only appear once, and the section
	@# for the version being built has to say something.
	@dupes=$$(grep -oE '^## \[[0-9][0-9.]*\]' CHANGELOG.md | sort | uniq -d | tr -d '#[] ' | tr '\n' ' '); \
	if [ -n "$$dupes" ]; then \
		printf "  ❌ %-14s duplicated: %s\n" "CHANGELOG" "$$dupes"; \
		echo "❌ A version may only have one section"; \
		exit 1; \
	fi; \
	body=$$(awk -v v='## [$(VERSION)]' 'index($$0, v) == 1 { f = 1; next } /^## \[/ { f = 0 } f' \
		CHANGELOG.md | tr -d '[:space:]'); \
	if [ -z "$$body" ]; then \
		printf "  ⚠️  %-14s section [$(VERSION)] is empty\n" "CHANGELOG"; \
		echo "   Fill it before releasing — \`make release\` refuses an empty section."; \
	else \
		printf "  ✅ %-14s section [$(VERSION)] has notes\n" "CHANGELOG"; \
	fi

# === Release ===

# Refuses a release whose notes were never written.
#
# `version-check` only *warns* about an empty section, because `bump` legitimately
# opens one before the notes exist. Here it is fatal: a published release with no
# notes cannot be taken back — 2.5.0 went out that way, and 2.8.1 again, because
# this check lived inside the `release` target and the tag-triggered workflow never
# reached it. It is its own target now, called from both paths.
changelog-check:
	@if [ -z "$$($(CHANGELOG_SECTION) | tr -d '[:space:]')" ]; then \
		echo "❌ CHANGELOG section [$(VERSION)] is empty — write the release notes first"; \
		exit 1; \
	fi
	@echo "✅ CHANGELOG section [$(VERSION)] has notes"

# The body of this version's CHANGELOG section — what a release is published with.
# `release-notes` prints it; `changelog-check` asks whether it is empty. One awk, so
# the notes that are checked are the notes that ship.
release-notes:
	@$(CHANGELOG_SECTION)

release: version-check app
	@echo "🚀 Releasing v$(VERSION)..."
	@# Checked before the clean-tree gate below on purpose — otherwise you commit
	@# first and only then learn the notes are missing, which needs a second commit.
	@$(MAKE) --no-print-directory changelog-check
	@# Ensure working tree is clean — commit changes before releasing
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "❌ Uncommitted changes. Run: /commit then make release"; \
		exit 1; \
	fi
	@# Zip the app
	cd build && zip -r $(APP_NAME)-$(VERSION).zip $(APP_NAME).app
	@# Create GitHub release, carrying this version's CHANGELOG section as the body.
	@# `--generate-notes` used to stand in for it and produced a bare compare link;
	@# what changed and why lives in the CHANGELOG, so that is what gets published.
	@$(MAKE) --no-print-directory release-notes > build/release-notes.md
	gh release create v$(VERSION) \
		build/$(APP_NAME)-$(VERSION).zip \
		--title "$(APP_NAME) $(VERSION)" \
		--notes-file build/release-notes.md
	@echo "✅ Released v$(VERSION)"

# === Install & Fix ===

install: app
	@echo "📲 Installing to /Applications..."
	@rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_DIR) /Applications/$(APP_NAME).app
	@echo "✅ Installed to /Applications/$(APP_NAME).app"

fix:
	@echo "🔧 Fixing Gatekeeper quarantine..."
	xattr -cr /Applications/$(APP_NAME).app
	codesign --force --deep --sign - /Applications/$(APP_NAME).app
	@echo "✅ Fixed. Run: open /Applications/$(APP_NAME).app"

# === Clean ===

clean:
	@echo "🧹 Cleaning..."
	swift package clean
	rm -rf build/
	rm -rf $(APPINTENTS_DIR)
	rm -f Resources/AppIcon.icns

# === Help ===

help:
	@echo ""
	@echo "📚 SmartDock — Makefile commands"
	@echo ""
	@echo "  Build & Run:"
	@echo "    make build         Build release binary"
	@echo "    make test          Run unit tests"
	@echo "    make app           Build .app bundle (ad-hoc signed)"
	@echo "    make run           Build + open the app"
	@echo "    make clean         Remove all build artifacts"
	@echo ""
	@echo "  Code quality:"
	@echo "    make format        Reformat Swift sources in place (swift-format)"
	@echo "    make lint          Check formatting without writing — CI gates on this"
	@echo "    make coverage      Run tests and print a per-file coverage table"
	@echo ""
	@echo "  Shortcuts & Spotlight:"
	@echo "    make appintents       Generate App Intents metadata (part of make app)"
	@echo "    make appintents-check Verify every declared intent reached the bundle"
	@echo ""
	@echo "  Bundle checks (both part of make app):"
	@echo "    make entitlements-check Verify the sealed bundle carries the entitlements file"
	@echo "    make sdef-check         Verify .sdef classes match ScriptingSupport.swift"
	@echo ""
	@echo "  Install:"
	@echo "    make install       Copy .app to /Applications"
	@echo "    make fix           Fix Gatekeeper quarantine on /Applications/SmartDock.app"
	@echo ""
	@echo "  Version & Release:"
	@echo "    make bump V=1.2.3  Bump version everywhere (Makefile, Info.plist, README badge)"
	@echo "    make version-check Verify all version references agree"
	@echo "    make changelog-check Verify this version's notes were written (gates releasing)"
	@echo "    make release-notes    Print this version's CHANGELOG section (the release body)"
	@echo "    make release       Build + zip + create GitHub release"
	@echo ""
	@echo "  Distribution (requires Developer ID):"
	@echo "    make sign          Sign with Developer ID"
	@echo "    make dmg           Create signed DMG"
	@echo "    make notarize      Submit DMG for notarization"
	@echo ""
	@echo "  Dependencies & tooling:"
	@echo "    make deps          Show SPM dependencies"
	@echo "    make outdated      Check Xcode/Swift/Actions versions"
	@echo "    make actions-check Compare GitHub Actions versions vs latest (requires gh)"
	@echo "    make doctor        Verify dev environment (swift, xcode, gh)"
	@echo "    make logs          Stream live SmartDock logs (Ctrl+C to stop)"
	@echo ""
	@echo "  Current version: $(VERSION)"
	@echo ""

# === Dependencies ===

deps:
	@echo "📦 Swift Package dependencies:"
	@swift package show-dependencies || echo "  (none — only Apple frameworks)"
	@echo ""
	@if [ -f Package.resolved ]; then \
		echo "🔒 Package.resolved exists:"; \
		swift package show-dependencies --format text; \
	else \
		echo "ℹ️  No Package.resolved — no external SPM dependencies"; \
	fi

outdated:
	@echo "🔍 Checking versions..."
	@echo ""
	@echo "Swift:"
	@swift --version | head -1 | sed 's/^/  /'
	@echo ""
	@echo "Xcode:"
	@xcodebuild -version | head -1 | sed 's/^/  /'
	@echo ""
	@echo "GitHub Actions in workflows:"
	@grep -h "uses: " .github/workflows/*.yml | sort -u | sed 's/^/  /'
	@echo ""
	@if command -v swift >/dev/null 2>&1; then \
		echo "🔄 Updating Package.resolved..."; \
		swift package update 2>&1 | sed 's/^/  /' || true; \
	fi

actions-check:
	@echo "🔎 Checking GitHub Actions versions..."
	@echo ""
	@command -v gh >/dev/null || { echo "❌ gh CLI not installed (brew install gh)"; exit 1; }
	@printf "%-35s %-12s %-12s %s\n" "ACTION" "CURRENT" "LATEST" "STATUS"
	@printf "%-35s %-12s %-12s %s\n" "------" "-------" "------" "------"
	@for line in $$(grep -h "uses: " .github/workflows/*.yml | sed 's/.*uses: //' | sort -u); do \
		action=$$(echo $$line | cut -d@ -f1); \
		current=$$(echo $$line | cut -d@ -f2); \
		latest=$$(gh api repos/$$action/releases/latest --jq .tag_name 2>/dev/null || echo "n/a"); \
		current_major=$$(echo $$current | sed 's/^v//' | cut -d. -f1); \
		latest_major=$$(echo $$latest | sed 's/^v//' | cut -d. -f1); \
		if [ "$$latest" = "n/a" ]; then \
			status="?"; \
		elif [ "$$current" = "$$latest" ]; then \
			status="✅ up-to-date"; \
		elif [ "$$current_major" = "$$latest_major" ]; then \
			status="✅ up-to-date (major pinned)"; \
		else \
			status="⬆️  major update: $$current → $$latest"; \
		fi; \
		printf "%-35s %-12s %-12s %s\n" "$$action" "$$current" "$$latest" "$$status"; \
	done

logs:
	@echo "📜 Streaming SmartDock logs (Ctrl+C to stop)..."
	@log stream --predicate 'subsystem == "com.smartdock.app"' --info --style compact

doctor:
	@echo "🩺 Checking dev environment..."
	@echo ""
	@printf "  Swift:       "; command -v swift >/dev/null && swift --version | head -1 || echo "❌ not installed"
	@printf "  Xcode:       "; command -v xcodebuild >/dev/null && xcodebuild -version | head -1 || echo "❌ not installed"
	@printf "  swift-format:"; xcrun --find swift-format >/dev/null 2>&1 && echo " ✅ $$(xcrun swift-format --version)" || echo " ❌ not in toolchain (needs Xcode 26+)"
	@printf "  llvm-cov:    "; xcrun --find llvm-cov >/dev/null 2>&1 && echo "✅ available" || echo "❌ not in toolchain"
	@printf "  codesign:    "; command -v codesign >/dev/null && echo "✅ available" || echo "❌ not installed"
	@printf "  gh:          "; command -v gh >/dev/null && gh --version | head -1 || echo "❌ not installed (brew install gh)"
	@printf "  git:         "; command -v git >/dev/null && git --version || echo "❌ not installed"
	@echo ""
	@echo "  Project version: $(VERSION)"
	@echo "  Working tree:    $$(git status --porcelain | wc -l | tr -d ' ') uncommitted change(s)"

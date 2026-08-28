.PHONY: help build test clean icon app run sign notarize fix install release bump version-check deps outdated doctor actions-check logs format lint coverage

.DEFAULT_GOAL := help

# === Config ===
APP_NAME     := SmartDock
BUNDLE_ID    := com.smartdock.app
VERSION      := 2.4.2
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

coverage:
	@echo "🧪 Running tests with coverage..."
	@swift test --enable-code-coverage
	@echo ""
	@bin=$$(swift build --show-bin-path); \
	prof=$$(swift test --show-codecov-path); \
	xcrun llvm-cov report \
		"$$bin/SmartDockPackageTests.xctest/Contents/MacOS/SmartDockPackageTests" \
		-instr-profile="$$(dirname $$prof)/default.profdata" \
		-ignore-filename-regex='.build|Tests/'

# === App Bundle ===

icon:
	@echo "🎨 Generating app icon..."
	cd $(CURDIR) && swift scripts/generate-icon.swift

app: build icon
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
	@if [ -f Resources/AppIcon.icns ]; then \
		cp Resources/AppIcon.icns $(RESOURCES)/AppIcon.icns; \
	fi

	@# Ad-hoc sign (free, no Developer ID needed)
	@# Required for macOS to allow opening the app
	codesign --force --deep \
		--entitlements Resources/SmartDock.entitlements \
		--sign - \
		$(APP_DIR)

	@echo "✅ $(APP_DIR) created (ad-hoc signed)"
	@echo "   Run: open $(APP_DIR)"

# === Run ===

run: app
	@echo "🚀 Launching $(APP_NAME)..."
	open $(APP_DIR)

# === Code Signing (for distribution) ===

sign: app
	@echo "🔐 Signing with: $(SIGN_ID)"
	codesign --force --deep --timestamp \
		--options runtime \
		--entitlements Resources/SmartDock.entitlements \
		--sign "$(SIGN_ID)" \
		$(APP_DIR)
	@echo "✅ Signed. Verify:"
	codesign --verify --verbose $(APP_DIR)

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

# === Release ===

release: version-check app
	@echo "🚀 Releasing v$(VERSION)..."
	@# Ensure working tree is clean — commit changes before releasing
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "❌ Uncommitted changes. Run: /commit then make release"; \
		exit 1; \
	fi
	@# Zip the app
	cd build && zip -r $(APP_NAME)-$(VERSION).zip $(APP_NAME).app
	@# Create GitHub release
	gh release create v$(VERSION) \
		build/$(APP_NAME)-$(VERSION).zip \
		--title "$(APP_NAME) $(VERSION)" \
		--generate-notes
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
	@echo "  Install:"
	@echo "    make install       Copy .app to /Applications"
	@echo "    make fix           Fix Gatekeeper quarantine on /Applications/SmartDock.app"
	@echo ""
	@echo "  Version & Release:"
	@echo "    make bump V=1.2.3  Bump version everywhere (Makefile, Info.plist, README badge)"
	@echo "    make version-check Verify all version references agree"
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

.PHONY: help build test clean icon app run sign notarize fix install release bump deps outdated doctor actions-check

.DEFAULT_GOAL := help

# === Config ===
APP_NAME     := SmartDock
BUNDLE_ID    := com.smartdock.app
VERSION      := 1.9.1
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
# Usage: make bump V=1.9.1

bump:
ifndef V
	$(error Usage: make bump V=1.9.1)
endif
	@echo "📌 Bumping version to $(V)..."
	sed -i '' 's/^VERSION      := .*/VERSION      := $(V)/' Makefile
	sed -i '' '/CFBundleShortVersionString/{n;s|<string>.*</string>|<string>$(V)</string>|;}' Resources/Info.plist
	@BUILD=$$(sed -n '/CFBundleVersion/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' Resources/Info.plist) && \
		NEW_BUILD=$$(( $$BUILD + 1 )) && \
		sed -i '' "/CFBundleVersion/{n;s|<string>.*</string>|<string>$$NEW_BUILD</string>|;}" Resources/Info.plist
	@echo "✅ Version: $(V), Build: $$(sed -n '/CFBundleVersion/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' Resources/Info.plist)"

# === Release ===

release: app
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
	@echo "  Install:"
	@echo "    make install       Copy .app to /Applications"
	@echo "    make fix           Fix Gatekeeper quarantine on /Applications/SmartDock.app"
	@echo ""
	@echo "  Version & Release:"
	@echo "    make bump V=1.2.3  Bump version in Makefile + Info.plist"
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

doctor:
	@echo "🩺 Checking dev environment..."
	@echo ""
	@printf "  Swift:       "; command -v swift >/dev/null && swift --version | head -1 || echo "❌ not installed"
	@printf "  Xcode:       "; command -v xcodebuild >/dev/null && xcodebuild -version | head -1 || echo "❌ not installed"
	@printf "  codesign:    "; command -v codesign >/dev/null && echo "✅ available" || echo "❌ not installed"
	@printf "  gh:          "; command -v gh >/dev/null && gh --version | head -1 || echo "❌ not installed (brew install gh)"
	@printf "  git:         "; command -v git >/dev/null && git --version || echo "❌ not installed"
	@echo ""
	@echo "  Project version: $(VERSION)"
	@echo "  Working tree:    $$(git status --porcelain | wc -l | tr -d ' ') uncommitted change(s)"

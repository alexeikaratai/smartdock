.PHONY: build test clean icon app run sign notarize fix install release bump

# === Config ===
APP_NAME     := SmartDock
BUNDLE_ID    := com.smartdock.app
VERSION      := 1.2.0
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
	swift test --parallel

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
# Usage: make bump V=1.3.0

bump:
ifndef V
	$(error Usage: make bump V=1.3.0)
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

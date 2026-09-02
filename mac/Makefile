# NTS Radio — native SwiftUI menu-bar app build.
# dev = run from source; build = release binary; app = .app bundle; dmg = installer.

APP        := NTSRadio
APP_NAME   := NTS Radio
CONFIG     := release
BUILD_DIR  := .build/$(CONFIG)
OUT        := build
APP_BUNDLE := $(OUT)/$(APP_NAME).app
FONT_SRC   := Sources/NTSRadio/Resources/Fonts
ICON_SRC   := Resources/AppIcon.icns

.PHONY: dev run-binary build app dmg install run clean

dev: ## Run from source; press R to rebuild & relaunch, Q to quit
	./dev.sh

build: ## Compile the release binary
	swift build -c $(CONFIG)

app: build ## Assemble the .app bundle (fonts bundled, mixtapes fetched live)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources" "$(APP_BUNDLE)/Contents/Frameworks"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp "$(BUILD_DIR)/$(APP)" "$(APP_BUNDLE)/Contents/MacOS/$(APP)"
	# Archivo, copied from source rather than from the SwiftPM resource bundle.
	# Theme.registerFonts() reads Contents/Resources directly; nothing in the
	# shipped app may reach into a build directory, which is what the old
	# Bundle.module path did — see the comment on registerFonts.
	cp "$(FONT_SRC)/Archivo.ttf" "$(APP_BUNDLE)/Contents/Resources/Archivo.ttf"
	cp "$(FONT_SRC)/OFL.txt" "$(APP_BUNDLE)/Contents/Resources/OFL.txt"
	# Sparkle.framework: the binary links it by @rpath, which only resolves
	# inside an app bundle's own Contents/Frameworks — `swift build` leaves it
	# sitting in .build/release, so without this copy the app is a "Library not
	# loaded" crash on every launch outside the SPM sandbox that built it.
	cp -R "$(BUILD_DIR)/Sparkle.framework" "$(APP_BUNDLE)/Contents/Frameworks/"
	# Scripting dictionary — the app's control surface. Info.plist points at it
	# by name (OSAScriptingDefinition), so it has to land in Resources/.
	cp Resources/NTSRadio.sdef "$(APP_BUNDLE)/Contents/Resources/NTSRadio.sdef"
	# Icon (reuse the existing NTS icon)
	cp "$(ICON_SRC)" "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns" 2>/dev/null || true
	# Stable-sign (Apple Development identity, fixed identifier) so macOS Keychain
	# grants persist across rebuilds. CODE_SIGN_IDENTITY=- forces ad-hoc (the dmg).
	./codesign-local.sh "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

dmg: ## Build a distributable .dmg from the .app (ad-hoc signed — no personal cert)
	CODE_SIGN_IDENTITY=- $(MAKE) app
	rm -f "$(OUT)/$(APP_NAME).dmg"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(APP_BUNDLE)" -ov -format UDZO "$(OUT)/$(APP_NAME).dmg"
	@echo "Built $(OUT)/$(APP_NAME).dmg"

notarize: app ## Build a Developer ID-signed, notarized .dmg (needs CODE_SIGN_IDENTITY="Developer ID Application: …" + the App Store Connect API key env vars)
	rm -f "$(OUT)/$(APP_NAME).dmg"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(APP_BUNDLE)" -ov -format UDZO "$(OUT)/$(APP_NAME).dmg"
	./notarize.sh "$(OUT)/$(APP_NAME).dmg"
	@echo "Built and notarized $(OUT)/$(APP_NAME).dmg"

install: app ## Install the .app into /Applications
	rm -rf "/Applications/$(APP_NAME).app"
	ditto "$(APP_BUNDLE)" "/Applications/$(APP_NAME).app"
	@echo "Installed to /Applications/$(APP_NAME).app"

run: app ## Build the .app and launch it
	open "$(APP_BUNDLE)"

clean: ## Remove build artifacts
	rm -rf .build "$(OUT)"

# NTS Radio — native SwiftUI menu-bar app build.
# dev = run from source; build = release binary; app = .app bundle; dmg = installer.

APP        := NTSRadio
APP_NAME   := NTS Radio
CONFIG     := release
BUILD_DIR  := .build/$(CONFIG)
OUT        := build
APP_BUNDLE := $(OUT)/$(APP_NAME).app
RES_BUNDLE := $(APP)_$(APP).bundle
ICON_SRC   := Resources/AppIcon.icns

.PHONY: dev run-binary build app dmg install run clean

dev: ## Run from source; press R to rebuild & relaunch, Q to quit
	./dev.sh

build: ## Compile the release binary
	swift build -c $(CONFIG)

app: build ## Assemble the .app bundle (fonts bundled, mixtapes fetched live)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp "$(BUILD_DIR)/$(APP)" "$(APP_BUNDLE)/Contents/MacOS/$(APP)"
	# SwiftPM resource bundle (Archivo font) — placed where Bundle.module looks
	cp -R "$(BUILD_DIR)/$(RES_BUNDLE)" "$(APP_BUNDLE)/Contents/Resources/" 2>/dev/null || true
	cp -R "$(BUILD_DIR)/$(RES_BUNDLE)" "$(APP_BUNDLE)/Contents/MacOS/" 2>/dev/null || true
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

install: app ## Install the .app into /Applications
	rm -rf "/Applications/$(APP_NAME).app"
	ditto "$(APP_BUNDLE)" "/Applications/$(APP_NAME).app"
	@echo "Installed to /Applications/$(APP_NAME).app"

run: app ## Build the .app and launch it
	open "$(APP_BUNDLE)"

clean: ## Remove build artifacts
	rm -rf .build "$(OUT)"

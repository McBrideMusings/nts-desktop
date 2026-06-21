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

dev: ## Run the app from source (fast iteration)
	swift run $(APP)

build: ## Compile the release binary
	swift build -c $(CONFIG)

app: build ## Assemble the .app bundle (mixtapes + fonts bundled, portable)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp "$(BUILD_DIR)/$(APP)" "$(APP_BUNDLE)/Contents/MacOS/$(APP)"
	# SwiftPM resource bundle (Archivo font) — placed where Bundle.module looks
	cp -R "$(BUILD_DIR)/$(RES_BUNDLE)" "$(APP_BUNDLE)/Contents/Resources/" 2>/dev/null || true
	cp -R "$(BUILD_DIR)/$(RES_BUNDLE)" "$(APP_BUNDLE)/Contents/MacOS/" 2>/dev/null || true
	# Bundle the mixtape catalog so the app is portable off this machine
	cp -R ../mixtapes "$(APP_BUNDLE)/Contents/Resources/mixtapes"
	# Icon (reuse the existing NTS icon)
	cp "$(ICON_SRC)" "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns" 2>/dev/null || true
	# Ad-hoc sign so it launches cleanly locally
	codesign --force --deep --sign - "$(APP_BUNDLE)" 2>/dev/null || true
	@echo "Built $(APP_BUNDLE)"

dmg: app ## Build a distributable .dmg from the .app
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

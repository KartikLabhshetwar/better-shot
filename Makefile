# BetterShot Makefile
#
# Recipes pipe xcodebuild into tail/grep. A shell pipeline reports the LAST
# command's status, so without pipefail a failed build exits 0 and looks green.
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# Usage:
#   make build        — Debug build
#   make release      — Release build
#   make run          — Build and launch (debug)
#   make dmg          — Create unsigned DMG for local testing
#   make clean        — Remove build artifacts
#   make lint         — Swift compiler warnings check
#   make test-build   — Full clean + release build to verify everything compiles
#   make version      — Print current version
#   make ship         — Signed release: build, sign, notarize, DMG (both architectures)

SCHEME       = BetterShot
PROJECT      = BetterShot.xcodeproj
CONFIG_DEBUG = Debug
CONFIG_REL   = Release
DERIVED_DIR  = .build
APP_DEBUG    = $(DERIVED_DIR)/Build/Products/$(CONFIG_DEBUG)/$(SCHEME).app
APP_RELEASE  = $(DERIVED_DIR)/Build/Products/$(CONFIG_REL)/$(SCHEME).app
VERSION     := $(shell python3 -c "import json; print(json.load(open('version.json'))['version'])")
BUILD_NUM   := $(shell python3 -c "import json; print(json.load(open('version.json'))['build'])")
DMG_NAME     = BetterShot-$(VERSION).dmg
DMG_DIR      = release

.PHONY: generate build release run dmg clean lint test-build version ship help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

generate: ## Sync version from version.json and regenerate the Xcode project
	@sed -i '' \
		-e 's/MARKETING_VERSION: ".*"/MARKETING_VERSION: "$(VERSION)"/' \
		-e 's/CURRENT_PROJECT_VERSION: ".*"/CURRENT_PROJECT_VERSION: "$(BUILD_NUM)"/' \
		project.yml
	@xcodegen generate

build: generate ## Debug build
	@echo "==> Building $(SCHEME) (Debug)..."
	@xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_DEBUG) \
		-derivedDataPath $(DERIVED_DIR) \
		build 2>&1 | tail -3
	@echo "==> $(APP_DEBUG)"

release: generate ## Release build (unsigned)
	@echo "==> Building $(SCHEME) (Release)..."
	@xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_REL) \
		-derivedDataPath $(DERIVED_DIR) \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		build 2>&1 | tail -3
	@echo "==> $(APP_RELEASE)"

run: build ## Build and launch (debug)
	@echo "==> Launching BetterShot..."
	@pkill -x BetterShot 2>/dev/null || true
	@sleep 1
	@open "$(APP_DEBUG)"

dmg: release ## Create unsigned DMG for local testing
	@echo "==> Creating DMG..."
	@mkdir -p $(DMG_DIR)/staging
	@cp -R "$(APP_RELEASE)" $(DMG_DIR)/staging/
	@ln -sf /Applications $(DMG_DIR)/staging/Applications
	@hdiutil create -volname "BetterShot" \
		-srcfolder $(DMG_DIR)/staging \
		-ov -format UDZO \
		"$(DMG_DIR)/$(DMG_NAME)" 2>/dev/null
	@rm -rf $(DMG_DIR)/staging
	@echo "==> $(DMG_DIR)/$(DMG_NAME)"

clean: ## Remove build artifacts
	@echo "==> Cleaning..."
	@rm -rf $(DERIVED_DIR)
	@rm -rf $(DMG_DIR)/staging
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true
	@echo "==> Clean."

lint: ## Check for compiler warnings
	@echo "==> Checking for warnings..."
	@xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_DEBUG) \
		-derivedDataPath $(DERIVED_DIR) \
		build 2>&1 | grep -E "warning:|error:" || echo "No warnings."

test-build: clean release ## Full clean + release build
	@echo "==> Test build passed."

ship: generate ## Signed release: build, sign, notarize, DMG (both architectures)
	@bash scripts/release.sh

version: ## Print current version
	@echo "$(VERSION)"

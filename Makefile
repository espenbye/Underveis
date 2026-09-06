# Underveis — developer workflow
# Personal overrides (signing team, toolchain path) live in a git-ignored Local.mk:
#   UNDERVEIS_TEAM=ABCDE12345
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
-include Local.mk

# Prefer the Xcode 27 beta when installed, otherwise whatever xcode-select points at (must be a
# full Xcode, not the Command Line Tools).
XCODE_BETA := /Applications/Xcode-27.0.0-beta.app/Contents/Developer
DEVELOPER_DIR ?= $(if $(wildcard $(XCODE_BETA)),$(XCODE_BETA),$(shell xcode-select -p))
UNDERVEIS_TEAM ?=
export DEVELOPER_DIR UNDERVEIS_TEAM

PROJECT  := Underveis.xcodeproj
SCHEME   := Underveis
SIM_OS   := 26.0
SIM_NAME := iPhone 17 Pro

.PHONY: generate open build build-ios build-mac run-mac clean

generate: ## Regenerate the Xcode project from project.yml
	xcodegen generate

open: generate ## Generate then open in Xcode
	open $(PROJECT)

build: build-ios build-mac ## Build for both platforms

build-ios: generate ## Build for the iOS Simulator (no signing required)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIM_NAME),OS=$(SIM_OS)' \
		-configuration Debug build | xcbeautify || true

build-mac: generate ## Build the macOS app (compile only, signing disabled)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-configuration Debug CODE_SIGNING_ALLOWED=NO build

run-mac: generate ## Build & run the macOS app
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -configuration Debug build

clean: ## Remove generated project and build artifacts
	rm -rf $(PROJECT) build DerivedData

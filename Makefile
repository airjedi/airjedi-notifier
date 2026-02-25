# AirJedi Build Automation
# Run `make help` for available targets

PROJECT_DIR := $(shell pwd)
PROJECT_NAME := AirJedi
APP_NAME := AirJedi Alerts
SCHEME := AirJedi
XCODEPROJ := $(PROJECT_DIR)/$(PROJECT_NAME).xcodeproj

# Find the DerivedData build path (handles the hash suffix)
DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData
BUILD_DIR = $(shell find $(DERIVED_DATA) -maxdepth 1 -name "$(PROJECT_NAME)-*" -type d 2>/dev/null | head -1)

.PHONY: all generate build run clean release install help

# Default target
all: build

# Generate Xcode project from project.yml
generate:
	@echo "Generating Xcode project..."
	xcodegen generate
	@echo "✓ Project generated"

# Build debug configuration
build: generate
	@echo "Building $(PROJECT_NAME) (Debug)..."
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Debug build
	@echo "✓ Build complete"

# Build release configuration
release: generate
	@echo "Building $(PROJECT_NAME) (Release)..."
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration Release build
	@echo "✓ Release build complete"

# Run the app (builds first if needed)
run: build
	@echo "Launching $(APP_NAME)..."
	@if [ -n "$(BUILD_DIR)" ]; then \
		open "$(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app"; \
	else \
		echo "Error: Build directory not found. Run 'make build' first."; \
		exit 1; \
	fi

# Clean build artifacts
clean:
	@echo "Cleaning..."
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) clean 2>/dev/null || true
	@if [ -n "$(BUILD_DIR)" ]; then \
		rm -rf "$(BUILD_DIR)"; \
		echo "✓ Removed DerivedData"; \
	fi
	@echo "✓ Clean complete"

# Install to /Applications (release build)
install: release
	@echo "Installing $(APP_NAME) to /Applications..."
	@if [ -n "$(BUILD_DIR)" ]; then \
		cp -R "$(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app" /Applications/; \
		echo "✓ Installed to /Applications/$(APP_NAME).app"; \
	else \
		echo "Error: Build directory not found."; \
		exit 1; \
	fi

# Show available targets
help:
	@echo "AirJedi Alerts Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  generate  - Generate Xcode project from project.yml"
	@echo "  build     - Build debug configuration (default)"
	@echo "  release   - Build release configuration"
	@echo "  run       - Build and run the app"
	@echo "  clean     - Remove build artifacts and DerivedData"
	@echo "  install   - Build release and copy to /Applications"
	@echo "  help      - Show this help message"

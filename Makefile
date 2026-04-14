APP_NAME := aimeter
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS := $(APP_BUNDLE)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
BINARY := $(MACOS)/$(APP_NAME)
ICON := Resources/AppIcon.icns

SOURCES := $(wildcard Sources/*.swift)
ARCH := $(shell uname -m)
SDK := $(shell xcrun --show-sdk-path 2>/dev/null)

SWIFTC_BASE := -parse-as-library -O -lsqlite3
ifneq ($(SDK),)
    SWIFTC_BASE += -sdk $(SDK)
endif
SWIFTC_FLAGS := $(SWIFTC_BASE) -target $(ARCH)-apple-macos14.0

.PHONY: build universal clean install run release

build: $(BINARY) $(CONTENTS)/Info.plist $(RESOURCES)/AppIcon.icns
	@echo "✓ $(APP_BUNDLE)"

$(BINARY): $(SOURCES)
	@mkdir -p $(MACOS)
	swiftc $(SWIFTC_FLAGS) $(SOURCES) -o $(BINARY)
	@codesign --force --sign - $(APP_BUNDLE) 2>/dev/null || true

$(CONTENTS)/Info.plist: Info.plist
	@mkdir -p $(CONTENTS)
	cp Info.plist $(CONTENTS)/Info.plist

$(RESOURCES)/AppIcon.icns: $(ICON)
	@mkdir -p $(RESOURCES)
	cp $(ICON) $(RESOURCES)/AppIcon.icns

# Universal binary (arm64 + x86_64) for distribution
universal: $(SOURCES) Info.plist
	@mkdir -p $(MACOS)
	swiftc $(SWIFTC_BASE) -target arm64-apple-macos14.0 $(SOURCES) -o $(BINARY)-arm64
	swiftc $(SWIFTC_BASE) -target x86_64-apple-macos14.0 $(SOURCES) -o $(BINARY)-x86_64
	lipo -create -output $(BINARY) $(BINARY)-arm64 $(BINARY)-x86_64
	rm $(BINARY)-arm64 $(BINARY)-x86_64
	@mkdir -p $(CONTENTS) $(RESOURCES)
	cp Info.plist $(CONTENTS)/Info.plist
	cp $(ICON) $(RESOURCES)/AppIcon.icns
	@codesign --force --sign - $(APP_BUNDLE)
	@echo "✓ Universal $(APP_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR)

install: build
	@mkdir -p ~/Applications
	cp -R $(APP_BUNDLE) ~/Applications/
	@echo "✓ Installed to ~/Applications/$(APP_NAME).app"

run: build
	@open $(APP_BUNDLE)

# Release: build universal + zip for distribution
release: universal
	cd $(BUILD_DIR) && zip -r $(APP_NAME).zip $(APP_NAME).app
	@echo "✓ $(BUILD_DIR)/$(APP_NAME).zip"

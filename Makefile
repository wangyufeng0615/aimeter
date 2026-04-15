APP_NAME := aimeter
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS := $(APP_BUNDLE)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
BINARY := $(MACOS)/$(APP_NAME)
ICON := Resources/AppIcon.icns
ENTITLEMENTS := Resources/aimeter.entitlements

SOURCES := $(wildcard Sources/*.swift)
ARCH := $(shell uname -m)
SDK := $(shell xcrun --show-sdk-path 2>/dev/null)

SWIFTC_BASE := -parse-as-library -O -lsqlite3
ifneq ($(SDK),)
    SWIFTC_BASE += -sdk $(SDK)
endif
SWIFTC_FLAGS := $(SWIFTC_BASE) -target $(ARCH)-apple-macos14.0

# Code signing. If DEVELOPER_ID env var is set (e.g. "Developer ID Application:
# Name (TEAMID)") uses real signing + secure timestamp, otherwise ad-hoc.
# Both modes enable Hardened Runtime so local builds match release behavior.
DEVELOPER_ID ?=
NOTARY_PROFILE ?= aimeter-notary

ifeq ($(DEVELOPER_ID),)
    CODESIGN_FLAGS := --force --options runtime --entitlements $(ENTITLEMENTS) --sign -
else
    CODESIGN_FLAGS := --force --options runtime --timestamp --entitlements $(ENTITLEMENTS) --sign "$(DEVELOPER_ID)"
endif

.PHONY: build universal clean install run release notarize

build: $(BINARY) $(CONTENTS)/Info.plist $(RESOURCES)/AppIcon.icns
	@codesign $(CODESIGN_FLAGS) $(APP_BUNDLE)
	@echo "✓ $(APP_BUNDLE)"

$(BINARY): $(SOURCES)
	@mkdir -p $(MACOS)
	swiftc $(SWIFTC_FLAGS) $(SOURCES) -o $(BINARY)

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
	@codesign $(CODESIGN_FLAGS) $(APP_BUNDLE)
	@codesign --verify --strict --verbose=2 $(APP_BUNDLE)
	@echo "✓ Universal $(APP_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR)

install: build
	@mkdir -p ~/Applications
	cp -R $(APP_BUNDLE) ~/Applications/
	@echo "✓ Installed to ~/Applications/$(APP_NAME).app"

run: build
	@open $(APP_BUNDLE)

# Release: universal build + zip. Ad-hoc signed unless DEVELOPER_ID is set,
# in which case the zip contains a Developer ID-signed (but not notarized) .app.
# For a user-ready release, use `notarize` instead.
release: universal
	cd $(BUILD_DIR) && rm -f $(APP_NAME).zip && zip -qr $(APP_NAME).zip $(APP_NAME).app
	@echo "✓ $(BUILD_DIR)/$(APP_NAME).zip"

# Notarize: sign with Developer ID, submit to Apple, staple ticket, re-zip.
# Requires:
#   - DEVELOPER_ID env var (e.g. "Developer ID Application: Name (TEAMID)")
#   - NOTARY_PROFILE keychain item stored via:
#       xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
#           --key <AuthKey.p8> --key-id <KEY_ID> --issuer <ISSUER_UUID>
notarize: universal
	@test -n "$(DEVELOPER_ID)" || { echo "ERROR: set DEVELOPER_ID env var"; exit 1; }
	cd $(BUILD_DIR) && rm -f $(APP_NAME).zip && zip -qr $(APP_NAME).zip $(APP_NAME).app
	xcrun notarytool submit $(BUILD_DIR)/$(APP_NAME).zip \
	    --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP_BUNDLE)
	xcrun stapler validate $(APP_BUNDLE)
	spctl -a -vvv -t install $(APP_BUNDLE)
	cd $(BUILD_DIR) && rm -f $(APP_NAME).zip && zip -qr $(APP_NAME).zip $(APP_NAME).app
	@echo "✓ Notarized: $(BUILD_DIR)/$(APP_NAME).zip"

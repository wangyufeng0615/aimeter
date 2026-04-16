APP_NAME := aimeter
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS := $(APP_BUNDLE)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
BINARY := $(MACOS)/$(APP_NAME)
ICON := Resources/AppIcon.icns
DEV_ENTITLEMENTS := Resources/aimeter.entitlements
APP_FRAMEWORKS := $(CONTENTS)/Frameworks

# Sparkle: vendored binary framework (see Package.swift comment).
# `make vendor-sparkle` downloads if missing; CI invokes this target before build.
SPARKLE_VERSION := 2.9.1
SPARKLE_URL := https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-for-Swift-Package-Manager.zip
SPARKLE_DIR := Vendor/Sparkle
SPARKLE_XCFW := $(SPARKLE_DIR)/Sparkle.xcframework
SPARKLE_FW_SRC := $(SPARKLE_XCFW)/macos-arm64_x86_64/Sparkle.framework
SPARKLE_FW_DST := $(APP_FRAMEWORKS)/Sparkle.framework
SOURCES := $(wildcard Sources/*.swift)
ARCH := $(shell uname -m)
SDK := $(shell xcrun --show-sdk-path 2>/dev/null)

# Link Sparkle.framework via @rpath so dyld finds it under Contents/Frameworks/
SPARKLE_FLAGS := -F $(SPARKLE_XCFW)/macos-arm64_x86_64 -framework Sparkle \
                 -Xlinker -rpath -Xlinker @loader_path/../Frameworks
ZIP_FLAGS := -c -k --sequesterRsrc --keepParent

SWIFTC_BASE := -parse-as-library -O -lsqlite3 $(SPARKLE_FLAGS)
ifneq ($(SDK),)
    SWIFTC_BASE += -sdk $(SDK)
endif
SWIFTC_FLAGS := $(SWIFTC_BASE) -target $(ARCH)-apple-macos14.0

# Code signing. If DEVELOPER_ID env var is set (e.g. "Developer ID Application:
# Name (TEAMID)") uses real signing + secure timestamp, otherwise ad-hoc.
# Both modes enable Hardened Runtime so local builds match release behavior.
#
# Three flag sets are needed because Sparkle's nested binaries must be signed
# WITHOUT the app's entitlements:
#   CODESIGN_APP      — main app bundle + its executable
#   CODESIGN_INNER    — nested Sparkle binaries (no entitlements override)
#   CODESIGN_PRESERVE — Sparkle's Downloader.xpc (keeps its built-in entitlements)
DEVELOPER_ID ?=
NOTARY_PROFILE ?= aimeter-notary
NOTARY_KEY ?=
NOTARY_KEY_ID ?=
NOTARY_ISSUER_ID ?=

ifeq ($(DEVELOPER_ID),)
    SIGN_IDENTITY := -
    TIMESTAMP_FLAG :=
else
    SIGN_IDENTITY := "$(DEVELOPER_ID)"
    TIMESTAMP_FLAG := --timestamp
endif

CODESIGN_BASE := --force --options runtime $(TIMESTAMP_FLAG)
ifeq ($(DEVELOPER_ID),)
    # Ad-hoc local builds need this temporary entitlement to load Sparkle under
    # Hardened Runtime. Developer ID distribution builds re-sign Sparkle with
    # the app's identity and should keep Library Validation enabled.
    CODESIGN_APP := $(CODESIGN_BASE) --entitlements $(DEV_ENTITLEMENTS) --sign $(SIGN_IDENTITY)
else
    CODESIGN_APP := $(CODESIGN_BASE) --sign $(SIGN_IDENTITY)
endif
CODESIGN_INNER := $(CODESIGN_BASE) --sign $(SIGN_IDENTITY)
CODESIGN_PRESERVE := $(CODESIGN_BASE) --preserve-metadata=entitlements --sign $(SIGN_IDENTITY)

ifneq ($(NOTARY_KEY),)
    NOTARY_FLAGS := --key "$(NOTARY_KEY)" --key-id "$(NOTARY_KEY_ID)" --issuer "$(NOTARY_ISSUER_ID)"
else
    NOTARY_FLAGS := --keychain-profile "$(NOTARY_PROFILE)"
endif

.PHONY: build universal clean install run release notarize vendor-sparkle

# --- Sparkle vendoring ------------------------------------------------------

# Always checked; downloads only if the xcframework directory is missing.
vendor-sparkle:
	@if [ ! -d "$(SPARKLE_XCFW)" ]; then \
	    echo "Downloading Sparkle $(SPARKLE_VERSION)..."; \
	    mkdir -p $(SPARKLE_DIR); \
	    curl -fL "$(SPARKLE_URL)" -o "$(SPARKLE_DIR)/Sparkle.zip" && \
	    (cd $(SPARKLE_DIR) && unzip -q Sparkle.zip && rm Sparkle.zip); \
	fi
	@test -d "$(SPARKLE_XCFW)" || { echo "ERROR: Sparkle not at $(SPARKLE_XCFW)"; exit 1; }

# --- Build ------------------------------------------------------------------

# Inside-out codesign for an app bundle with embedded Sparkle.
# Do NOT use --deep: it mis-signs Sparkle's Downloader XPC entitlements.
# Order: innermost XPCs → Autoupdate helper → Updater.app → framework →
#        main binary → outermost app bundle.
define codesign_bundle
	codesign $(CODESIGN_INNER)    $(SPARKLE_FW_DST)/Versions/B/XPCServices/Installer.xpc
	codesign $(CODESIGN_PRESERVE) $(SPARKLE_FW_DST)/Versions/B/XPCServices/Downloader.xpc
	codesign $(CODESIGN_INNER)    $(SPARKLE_FW_DST)/Versions/B/Autoupdate
	codesign $(CODESIGN_INNER)    $(SPARKLE_FW_DST)/Versions/B/Updater.app
	codesign $(CODESIGN_INNER)    $(SPARKLE_FW_DST)
	codesign $(CODESIGN_APP)      $(BINARY)
	codesign $(CODESIGN_APP)      $(APP_BUNDLE)
endef

build: vendor-sparkle $(BINARY) $(CONTENTS)/Info.plist $(RESOURCES)/AppIcon.icns $(SPARKLE_FW_DST)
	@$(call codesign_bundle)
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

# Copy Sparkle into the bundle. `--delete` ensures stale files from older
# Sparkle versions don't linger across rebuilds.
$(SPARKLE_FW_DST): $(SPARKLE_FW_SRC)
	@mkdir -p $(APP_FRAMEWORKS)
	rsync -a --delete $(SPARKLE_FW_SRC)/ $(SPARKLE_FW_DST)/

# Universal binary (arm64 + x86_64) for distribution
universal: vendor-sparkle $(SOURCES) Info.plist
	@mkdir -p $(MACOS)
	swiftc $(SWIFTC_BASE) -target arm64-apple-macos14.0 $(SOURCES) -o $(BINARY)-arm64
	swiftc $(SWIFTC_BASE) -target x86_64-apple-macos14.0 $(SOURCES) -o $(BINARY)-x86_64
	lipo -create -output $(BINARY) $(BINARY)-arm64 $(BINARY)-x86_64
	rm $(BINARY)-arm64 $(BINARY)-x86_64
	@mkdir -p $(CONTENTS) $(RESOURCES) $(APP_FRAMEWORKS)
	cp Info.plist $(CONTENTS)/Info.plist
	cp $(ICON) $(RESOURCES)/AppIcon.icns
	rsync -a --delete $(SPARKLE_FW_SRC)/ $(SPARKLE_FW_DST)/
	@$(call codesign_bundle)
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
	cd $(BUILD_DIR) && rm -f $(APP_NAME).zip && \
	    ditto $(ZIP_FLAGS) $(APP_NAME).app $(APP_NAME).zip
	@echo "✓ $(BUILD_DIR)/$(APP_NAME).zip"

# Notarize: sign with Developer ID, submit to Apple, staple ticket, re-zip.
# Requires DEVELOPER_ID env var. Notary auth: either set NOTARY_KEY +
# NOTARY_KEY_ID + NOTARY_ISSUER_ID (CI), or use a stored keychain
# profile via NOTARY_PROFILE (local, default: aimeter-notary).
notarize: universal
	@test -n "$(DEVELOPER_ID)" || { echo "ERROR: set DEVELOPER_ID env var"; exit 1; }
	cd $(BUILD_DIR) && rm -f $(APP_NAME).zip && \
	    ditto $(ZIP_FLAGS) $(APP_NAME).app $(APP_NAME).zip
	xcrun notarytool submit $(BUILD_DIR)/$(APP_NAME).zip \
	    $(NOTARY_FLAGS) --wait
	xcrun stapler staple $(APP_BUNDLE)
	xcrun stapler validate $(APP_BUNDLE)
	spctl -a -vvv -t execute $(APP_BUNDLE)
	cd $(BUILD_DIR) && rm -f $(APP_NAME).zip && \
	    ditto $(ZIP_FLAGS) $(APP_NAME).app $(APP_NAME).zip
	@echo "✓ Notarized: $(BUILD_DIR)/$(APP_NAME).zip"

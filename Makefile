SCHEME  := Overhang
PROJECT := Overhang.xcodeproj
CONFIG  := Release
DERIVED := build
APP     := $(DERIVED)/Build/Products/$(CONFIG)/Overhang.app

# Ad-hoc signing by default. Override to keep Accessibility grants across rebuilds:
#   make install SIGN_ID="Apple Development: Your Name (XXXXXXXXXX)" TEAM_ID=YYYYYYYYYY
SIGN_ID ?= -
TEAM_ID ?=

SIGNFLAGS := CODE_SIGN_IDENTITY="$(SIGN_ID)"
ifneq ($(strip $(TEAM_ID)),)
SIGNFLAGS += DEVELOPMENT_TEAM=$(TEAM_ID)
endif

.PHONY: all project build test install run clean icon release dmg notarize-dmg notarize-zip verify lint

all: build

project: $(PROJECT)

$(PROJECT): project.yml
	xcodegen generate

build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) $(SIGNFLAGS) build

test: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="-" test

install: build
	@pkill -x Overhang || true
	rm -rf /Applications/Overhang.app
	cp -R $(APP) /Applications/
	@echo "installed → /Applications/Overhang.app"

run: install
	open /Applications/Overhang.app

# Regenerates Sources/Overhang.icns from Tools/makeicon.swift.
icon:
	@rm -rf Overhang.iconset && mkdir -p Overhang.iconset
	swift Tools/makeicon.swift Overhang.iconset
	iconutil -c icns Overhang.iconset -o Sources/Overhang.icns
	@rm -rf Overhang.iconset
	@echo "wrote Sources/Overhang.icns"

# Zips the built app for attaching to a GitHub release.
release: build
	@rm -f Overhang.zip
	ditto -c -k --keepParent $(APP) Overhang.zip
	@echo "wrote Overhang.zip"

# Builds a drag-to-install disk image.
dmg: build
	@rm -f Overhang.dmg
	@rm -rf $(DERIVED)/dmgroot && mkdir -p $(DERIVED)/dmgroot
	cp -R $(APP) $(DERIVED)/dmgroot/
	create-dmg \
		--volname "Overhang" \
		--window-pos 200 120 --window-size 560 380 \
		--icon-size 110 \
		--icon "Overhang.app" 150 175 \
		--app-drop-link 410 175 \
		--hide-extension "Overhang.app" \
		--no-internet-enable \
		Overhang.dmg $(DERIVED)/dmgroot
	@rm -rf $(DERIVED)/dmgroot
	@echo "wrote Overhang.dmg"

# ---------------------------------------------------------------- notarization
# Needs a Developer ID Application certificate and a stored notarytool profile:
#   xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
#       --apple-id you@example.com --team-id $(TEAM_ID) --password <app-specific-password>
NOTARY_PROFILE ?= overhang

notarize-dmg: dmg
	xcrun notarytool submit Overhang.dmg --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple Overhang.dmg
	@echo "stapled Overhang.dmg"

notarize-zip: release
	xcrun notarytool submit Overhang.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	@echo "note: a zip cannot be stapled. Staple the .app, then rezip:"
	@echo "  xcrun stapler staple $(APP) && ditto -c -k --keepParent $(APP) Overhang.zip"

# Confirms Gatekeeper would accept the built app.
verify:
	codesign -dv --verbose=2 $(APP) 2>&1 | grep -E "Authority|TeamIdentifier|flags" || true
	@echo "--- gatekeeper assessment ---"
	spctl -a -vvv -t install $(APP) || true
	@echo "--- notarization ticket stapled? ---"
	xcrun stapler validate $(APP) || true

lint:
	swiftlint --quiet || true
	swiftformat --lint Sources Tests || true

clean:
	rm -rf $(DERIVED) $(PROJECT) Overhang.zip Overhang.iconset

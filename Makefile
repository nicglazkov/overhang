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

.PHONY: all project build test install run clean icon release dmg notarize verify lint

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

# Zips the built app for attaching to a GitHub release. For the notarized release
# artifacts use `make notarize`, which staples the app before zipping.
release: build
	@rm -f Overhang.zip
	ditto -c -k --keepParent $(APP) Overhang.zip
	@echo "wrote Overhang.zip"

# Builds a drag-to-install disk image from the app as it currently exists in build/.
# Not part of the release flow on its own: an app packaged before notarization has no
# ticket, and stapling the finished DMG does not staple the app sealed inside it.
dmg:
	@test -d $(APP) || { echo "no built app at $(APP); run make build first"; exit 1; }
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
NOTARY_PROFILE ?= notary

# The complete release flow, in the only order that staples everything.
#
# Two notarytool submissions, deliberately. Notarizing only the DMG leaves the app
# inside it unstapled, because the DMG is assembled before the ticket exists.
# Gatekeeper still passes such an app by querying Apple online, so the gap is
# invisible on a connected machine and blocks a user whose first launch is offline.
#
#   1. build and sign
#   2. submit the app itself (as a temp zip), staple the app
#   3. build the DMG around the now stapled app, submit it, staple it
#   4. zip the stapled app for the release asset
#   5. verify both artifacts
notarize: build
	@# -- preflight the signature notarization will require. Output is captured once
	@# rather than piped into grep -q: under pipefail, grep exiting early on a match
	@# sends SIGPIPE to codesign and the pipeline reports failure despite passing.
	@set -e; SIGINFO="$$(codesign -dv --verbose=4 $(APP) 2>&1)"; \
	ENTS="$$(codesign -d --entitlements - $(APP) 2>/dev/null || true)"; \
	case "$$SIGINFO" in *"flags=0x10000(runtime)"*) ;; \
	  *) echo "hardened runtime missing, notarization will fail"; exit 1;; esac; \
	case "$$ENTS" in *get-task-allow*) \
	  echo "get-task-allow present, notarization will fail"; exit 1;; *) ;; esac; \
	case "$$SIGINFO" in *"Authority=Developer ID Application"*) ;; \
	  *) echo "not signed with Developer ID, notarization will fail"; exit 1;; esac; \
	echo "preflight ok: hardened runtime, no get-task-allow, Developer ID"
	@# -- notarize and staple the app first
	@rm -f $(DERIVED)/notarize-app.zip
	ditto -c -k --keepParent $(APP) $(DERIVED)/notarize-app.zip
	xcrun notarytool submit $(DERIVED)/notarize-app.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP)
	@rm -f $(DERIVED)/notarize-app.zip
	@# -- package the stapled app, then notarize and staple the DMG itself
	$(MAKE) dmg
	xcrun notarytool submit Overhang.dmg --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple Overhang.dmg
	@# -- the zip carries the app's ticket because the app was stapled before zipping
	@rm -f Overhang.zip
	ditto -c -k --keepParent $(APP) Overhang.zip
	$(MAKE) verify

# Confirms Gatekeeper would accept the artifacts, offline included.
verify:
	codesign -dv --verbose=2 $(APP) 2>&1 | grep -E "Authority|TeamIdentifier|flags" || true
	@echo "--- gatekeeper assessment ---"
	spctl -a -vvv -t install $(APP) || true
	@echo "--- ticket stapled to the app? ---"
	xcrun stapler validate $(APP) || true
	@echo "--- ticket stapled to the DMG? ---"
	@test -f Overhang.dmg && xcrun stapler validate Overhang.dmg || echo "(no Overhang.dmg present)"
	@echo "--- architectures ---"
	@lipo -archs $(APP)/Contents/MacOS/Overhang || true

lint:
	swiftlint --quiet || true
	swiftformat --lint Sources Tests || true

clean:
	rm -rf $(DERIVED) $(PROJECT) Overhang.zip Overhang.iconset

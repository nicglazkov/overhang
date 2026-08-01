SCHEME  := Overflow
PROJECT := Overflow.xcodeproj
CONFIG  := Release
DERIVED := build
APP     := $(DERIVED)/Build/Products/$(CONFIG)/Overflow.app

# Ad-hoc signing by default. Override to keep Accessibility grants across rebuilds:
#   make install SIGN_ID="Apple Development: Your Name (XXXXXXXXXX)" TEAM_ID=YYYYYYYYYY
SIGN_ID ?= -
TEAM_ID ?=

SIGNFLAGS := CODE_SIGN_IDENTITY="$(SIGN_ID)"
ifneq ($(strip $(TEAM_ID)),)
SIGNFLAGS += DEVELOPMENT_TEAM=$(TEAM_ID)
endif

.PHONY: all project build test install run clean icon release lint

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
	@pkill -x Overflow || true
	rm -rf /Applications/Overflow.app
	cp -R $(APP) /Applications/
	@echo "installed → /Applications/Overflow.app"

run: install
	open /Applications/Overflow.app

# Regenerates Sources/Overflow.icns from Tools/makeicon.swift.
icon:
	@rm -rf Overflow.iconset && mkdir -p Overflow.iconset
	swift Tools/makeicon.swift Overflow.iconset
	iconutil -c icns Overflow.iconset -o Sources/Overflow.icns
	@rm -rf Overflow.iconset
	@echo "wrote Sources/Overflow.icns"

# Zips the built app for attaching to a GitHub release.
release: build
	@rm -f Overflow.zip
	ditto -c -k --keepParent $(APP) Overflow.zip
	@echo "wrote Overflow.zip"

lint:
	swiftlint --quiet || true
	swiftformat --lint Sources Tests || true

clean:
	rm -rf $(DERIVED) $(PROJECT) Overflow.zip Overflow.iconset

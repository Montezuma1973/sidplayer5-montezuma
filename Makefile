.PHONY: build adhoc-sign unquarantine run archive clean

PROJECT := SIDPLAY.xcodeproj
SCHEME := SIDPLAY
CONFIGURATION ?= Release
DERIVED_DATA ?= build/DerivedData
BUILD_PRODUCTS := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)
APP := $(BUILD_PRODUCTS)/SIDPLAY.app

MACOSX_DEPLOYMENT_TARGET ?= 12.0

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) MACOSX_DEPLOYMENT_TARGET=$(MACOSX_DEPLOYMENT_TARGET)

build:
	$(XCODEBUILD) build \
	  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_STYLE=Manual \
	  -derivedDataPath $(DERIVED_DATA)

adhoc-sign:
	codesign --force --sign - $(APP)/Contents/PlugIns/SIDTuneViewer.appex
	codesign --force --sign - $(APP)/Contents/Frameworks/*
	codesign --force --sign - $(APP)/Contents/MacOS/psid64
	codesign --force --sign - $(APP)/Contents/Library/Spotlight/SIDMusic.mdimporter
	codesign --force --sign - $(APP)

unquarantine:
	xattr -dr com.apple.quarantine $(APP)

run: build adhoc-sign unquarantine
	open $(APP)

archive:
	$(XCODEBUILD) archive -archivePath build/SIDPLAY.xcarchive

clean:
	rm -rf $(DERIVED_DATA)

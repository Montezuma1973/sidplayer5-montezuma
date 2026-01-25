#!/usr/bin/env bash
set -euo pipefail

PROJECT="SIDPLAY.xcodeproj"
SCHEME="SIDPLAY"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/DerivedData}"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/SIDPLAY.app"
CLEAR_QUARANTINE="${CLEAR_QUARANTINE:-0}"

echo "Building ${SCHEME} (${CONFIGURATION})..."
xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_STYLE=Manual \
  -derivedDataPath "${DERIVED_DATA_PATH}"

echo "Ad-hoc signing embedded components..."
codesign --force --sign - "${APP_PATH}/Contents/PlugIns/SIDTuneViewer.appex"
codesign --force --sign - "${APP_PATH}/Contents/Frameworks/"*
codesign --force --sign - "${APP_PATH}/Contents/MacOS/psid64"
codesign --force --sign - "${APP_PATH}/Contents/Library/Spotlight/SIDMusic.mdimporter"

echo "Ad-hoc signing app..."
codesign --force --sign - "${APP_PATH}"

if [[ "${CLEAR_QUARANTINE}" == "1" ]]; then
  echo "Clearing quarantine..."
  xattr -dr com.apple.quarantine "${APP_PATH}"
fi

echo "Verifying signature..."
codesign --verify --deep --strict "${APP_PATH}"

echo "Launching app..."
open "${APP_PATH}"

echo "Done: ${APP_PATH}"

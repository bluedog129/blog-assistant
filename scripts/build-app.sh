#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_PATH="$PWD/dist/BlogAssistant.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/BlogAssistant" "$APP_PATH/Contents/MacOS/BlogAssistant"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
# Finder can attach metadata to an existing app that codesign rejects.
xattr -cr "$APP_PATH"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --entitlements Resources/BlogAssistant.entitlements "$APP_PATH"
codesign --verify --strict "$APP_PATH"
printf 'Built app: %s\n' "$APP_PATH"

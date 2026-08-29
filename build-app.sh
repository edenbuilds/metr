#!/bin/zsh
# Builds metr.app.
#   ./build-app.sh            release build
#   ./build-app.sh debug      debug build
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"

# Regenerate the icon from the same geometry the app draws at runtime.
if [[ ! -f Branding/metr.icns ]]; then
  swift Tools/make-icons.swift
  iconutil -c icns Branding/metr.iconset -o Branding/metr.icns
fi

if [[ "$CONFIG" == "release" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BINARY=".build/apple/Products/Release/metr"
  STATUSLINE_BINARY=".build/apple/Products/Release/metr-statusline"
  RESOURCE_BUNDLE=".build/apple/Products/Release/metr_Metr.bundle"
else
  swift build -c "$CONFIG"
  BINARY=".build/$CONFIG/metr"
  STATUSLINE_BINARY=".build/$CONFIG/metr-statusline"
  RESOURCE_BUNDLE=".build/$CONFIG/metr_Metr.bundle"
fi

APP_DIR="$(pwd)/metr.app"
if [[ -e "$APP_DIR" ]]; then
  OLD_APP="$(mktemp -d "${TMPDIR:-/tmp}/metr-old-app.XXXXXX")"
  mv "$APP_DIR" "$OLD_APP/"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Helpers" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/metr"
cp "$STATUSLINE_BINARY" "$APP_DIR/Contents/Helpers/metr-statusline"
cp Info.plist "$APP_DIR/Contents/Info.plist"
cp Branding/metr.icns "$APP_DIR/Contents/Resources/metr.icns"
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"

# Ad-hoc signature: enough to run locally and register a login item. Sign the
# nested helper first so Gatekeeper sees a coherent bundle. Sending it to
# another Mac needs a Developer ID and notarisation — see README.
codesign --force --sign - "$APP_DIR/Contents/Helpers/metr-statusline" >/dev/null
codesign --force --sign - "$APP_DIR" >/dev/null
echo "Built $APP_DIR ($CONFIG)"

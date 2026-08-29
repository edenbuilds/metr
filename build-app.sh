#!/bin/zsh
# Builds Tidemark.app.
#   ./build-app.sh            release build
#   ./build-app.sh debug      debug build
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"

# Regenerate the icon from the same geometry the app draws at runtime.
if [[ ! -f Branding/Tidemark.icns ]]; then
  swift Tools/make-icons.swift
  iconutil -c icns Branding/Tidemark.iconset -o Branding/Tidemark.icns
fi

swift build -c "$CONFIG"

APP_DIR="$(pwd)/Tidemark.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/$CONFIG/Tidemark" "$APP_DIR/Contents/MacOS/Tidemark"
cp Info.plist "$APP_DIR/Contents/Info.plist"
cp Branding/Tidemark.icns "$APP_DIR/Contents/Resources/Tidemark.icns"

# Ad-hoc signature: enough to run locally and register a login item. Sending it
# to another Mac needs a Developer ID and notarisation — see README.
codesign --force --sign - "$APP_DIR" >/dev/null
echo "Built $APP_DIR ($CONFIG)"

#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.5.1"
RELEASE_DIR="$(pwd)/release"
STAGING_DIR="$RELEASE_DIR/dmg"

./build-app.sh release
if [[ -e "$RELEASE_DIR" ]]; then
  OLD_RELEASE="$(mktemp -d "${TMPDIR:-/tmp}/metr-old-release.XXXXXX")"
  mv "$RELEASE_DIR" "$OLD_RELEASE/"
fi
mkdir -p "$STAGING_DIR"
cp -R metr.app "$STAGING_DIR/metr.app"
cp INSTALL.txt "$STAGING_DIR/INSTALL.txt"
ln -s /Applications "$STAGING_DIR/Applications"

ditto -c -k --sequesterRsrc --keepParent metr.app "$RELEASE_DIR/metr-v$VERSION.zip"
hdiutil create -volname "metr" -srcfolder "$STAGING_DIR" -ov -format UDZO "$RELEASE_DIR/metr-v$VERSION.dmg" >/dev/null
OLD_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/metr-old-staging.XXXXXX")"
mv "$STAGING_DIR" "$OLD_STAGING/"

echo "Packaged:"
echo "  $RELEASE_DIR/metr-v$VERSION.dmg"
echo "  $RELEASE_DIR/metr-v$VERSION.zip"

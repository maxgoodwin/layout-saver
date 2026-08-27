#!/bin/bash
# Builds layout-saver and assembles it into a proper Layout Saver.app bundle,
# installed to ~/Applications so Spotlight/Launch Services indexes it like any
# other app.
#
# SwiftPM's `swift build` only produces a bare executable, not an app bundle —
# this script does the rest by hand rather than requiring a full Xcode project.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Layout Saver"
EXECUTABLE_NAME="layout-saver"
CONFIGURATION="release"
INSTALL_DIR="${LAYOUT_SAVER_INSTALL_DIR:-$HOME/Applications}"

VERSION=$(grep -m1 '^let version' "Sources/$EXECUTABLE_NAME/main.swift" | sed -E 's/.*"([^"]*)".*/\1/')
if [[ -z "$VERSION" ]]; then
    echo "error: could not read version from Sources/$EXECUTABLE_NAME/main.swift" >&2
    exit 1
fi

echo "==> Building $EXECUTABLE_NAME $VERSION ($CONFIGURATION)"
swift build -c "$CONFIGURATION"

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp ".build/$CONFIGURATION/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
sed "s/@VERSION@/$VERSION/g" Resources/Info.plist.template > "$APP_BUNDLE/Contents/Info.plist"
plutil -lint "$APP_BUNDLE/Contents/Info.plist" > /dev/null

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"

echo "==> Registering with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/$APP_NAME.app"

echo "==> Done: $INSTALL_DIR/$APP_NAME.app"
echo "    It should now appear in Spotlight search for \"Layout Saver\" (may take a few seconds to index)."

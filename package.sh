#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SimulTrans"
APP_TEMPLATE="$ROOT_DIR/AppTemplate"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
SIGNING_ID="${SIGNING_ID:-}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_TEMPLATE/Contents/Info.plist")}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

prepare_app_bundle() {
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
    cp "$APP_TEMPLATE/Contents/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
    cp "$APP_TEMPLATE/Contents/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    cp "$ROOT_DIR/.build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
}

sign_app_bundle() {
    if [[ -n "$SIGNING_ID" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$SIGNING_ID"; then
        codesign --force --deep --sign "$SIGNING_ID" "$APP_BUNDLE"
        echo "    Signed with: $SIGNING_ID"
    else
        codesign --force --deep --sign - "$APP_BUNDLE"
        echo "    Signed with: ad-hoc"
    fi
}

echo "=== Building ${APP_NAME} v${VERSION} ==="
cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"

echo "[1/4] Building release binary..."
swift build -c release

echo "[2/4] Creating app bundle..."
prepare_app_bundle

echo "[3/4] Code signing..."
sign_app_bundle

echo "[4/4] Creating DMG..."
rm -f "$DMG_PATH"
DMG_TMP="$(mktemp -d "${TMPDIR:-/tmp}/simultrans.XXXXXX")"
cp -R "$APP_BUNDLE" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TMP" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_TMP"

echo ""
echo "Output: $DMG_PATH"
echo "Size:   $(du -h "$DMG_PATH" | cut -f1)"

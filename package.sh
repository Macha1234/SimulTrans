#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SimulTrans"
APP_TEMPLATE="$ROOT_DIR/AppTemplate"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
SIGNING_ID="${SIGNING_ID:-}"
PREFERRED_SIGNING_ID="${PREFERRED_SIGNING_ID:-SimulTrans Dev}"
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

resolve_signing_identity() {
    if [[ -n "$SIGNING_ID" ]]; then
        return
    fi

    if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$PREFERRED_SIGNING_ID"; then
        SIGNING_ID="$PREFERRED_SIGNING_ID"
    fi
}

sign_app_bundle() {
    if [[ -n "$SIGNING_ID" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$SIGNING_ID"; then
        codesign --force --deep --sign "$SIGNING_ID" "$APP_BUNDLE"
        echo "    署名に使用した証明書: $SIGNING_ID"
    else
        codesign --force --deep --sign - "$APP_BUNDLE"
        echo "    ad-hoc 署名を使用します"
    fi
}

echo "=== ${APP_NAME} v${VERSION} をビルドします ==="
cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"

echo "[1/4] Release ビルドを実行中..."
swift build -c release

echo "[2/4] app bundle を作成中..."
prepare_app_bundle

echo "[3/4] コード署名を実行中..."
resolve_signing_identity
sign_app_bundle

echo "[4/4] DMG を作成中..."
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
echo "出力先: $DMG_PATH"
echo "サイズ: $(du -h "$DMG_PATH" | cut -f1)"

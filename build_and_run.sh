#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SimulTrans"
APP_TEMPLATE="$ROOT_DIR/AppTemplate"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
CONFIGURATION="${CONFIGURATION:-debug}"
SIGNING_ID="${SIGNING_ID:-}"

if [[ "$CONFIGURATION" == "release" ]]; then
    BUILD_OUTPUT_DIR="$ROOT_DIR/.build/release"
else
    BUILD_OUTPUT_DIR="$ROOT_DIR/.build/debug"
fi

prepare_app_bundle() {
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
    cp "$APP_TEMPLATE/Contents/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
    cp "$APP_TEMPLATE/Contents/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    cp "$BUILD_OUTPUT_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
}

sign_app_bundle() {
    if [[ -n "$SIGNING_ID" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$SIGNING_ID"; then
        codesign --force --deep --sign "$SIGNING_ID" "$APP_BUNDLE"
        echo "署名に使用した証明書: $SIGNING_ID"
    else
        codesign --force --deep --sign - "$APP_BUNDLE"
        echo "ad-hoc 署名で起動します"
    fi
}

echo "ビルド中 ($CONFIGURATION)..."
cd "$ROOT_DIR"
if [[ "$CONFIGURATION" == "release" ]]; then
    swift build -c release
else
    swift build
fi

echo "dist/ に app bundle を作成しています..."
mkdir -p "$DIST_DIR"
prepare_app_bundle
sign_app_bundle

echo "アプリを起動します..."
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
open "$APP_BUNDLE"

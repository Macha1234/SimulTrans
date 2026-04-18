#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SimulTrans"
APP_TEMPLATE="$ROOT_DIR/AppTemplate"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/${APP_NAME}.app"
CONFIGURATION="${CONFIGURATION:-debug}"
SIGNING_ID="${SIGNING_ID:-}"
PREFERRED_SIGNING_ID="${PREFERRED_SIGNING_ID:-SimulTrans Dev}"

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
    # Copy any .lproj folders (InfoPlist.strings localization)
    for lproj in "$APP_TEMPLATE/Contents/Resources/"*.lproj; do
        [[ -d "$lproj" ]] || continue
        cp -R "$lproj" "$APP_BUNDLE/Contents/Resources/"
    done
    cp "$BUILD_OUTPUT_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    # SwiftPM executable targets emit resource bundles next to the binary.
    for bundle in "$BUILD_OUTPUT_DIR"/*.bundle; do
        [[ -d "$bundle" ]] || continue
        cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
    done
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
        echo "署名に使用した証明書: $SIGNING_ID"
    else
        codesign --force --deep --sign - "$APP_BUNDLE"
        echo "ad-hoc 署名で起動します"
    fi
}

install_app_bundle() {
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALLED_APP_BUNDLE"
    ditto "$APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
    xattr -dr com.apple.quarantine "$INSTALLED_APP_BUNDLE" >/dev/null 2>&1 || true
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
resolve_signing_identity
sign_app_bundle
install_app_bundle

echo "アプリを起動します..."
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
open "$INSTALLED_APP_BUNDLE"

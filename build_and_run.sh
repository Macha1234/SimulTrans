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
    BUILD_ARGS=(-c release)
    BUILD_OUTPUT_DIR="$ROOT_DIR/.build/release"
else
    BUILD_ARGS=()
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
        echo "Signed with identity: $SIGNING_ID"
    else
        codesign --force --deep --sign - "$APP_BUNDLE"
        echo "Signed with ad-hoc identity"
    fi
}

echo "Building ($CONFIGURATION)..."
cd "$ROOT_DIR"
swift build "${BUILD_ARGS[@]}"

echo "Creating app bundle in dist/..."
mkdir -p "$DIST_DIR"
prepare_app_bundle
sign_app_bundle

echo "Launching..."
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
open "$APP_BUNDLE"

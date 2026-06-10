#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CopyPaste"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
ZIP_PATH="$OUTPUT_DIR/${APP_NAME}-universal.zip"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"

if [[ -e "$APP_DIR" ]]; then
    rm -rf "$APP_DIR"
    echo "Removed previous $APP_DIR"
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
BUILD_DIR="$ROOT_DIR/.build/objc"
UNIVERSAL_PRODUCT="$BUILD_DIR/$APP_NAME"

mkdir -p "$BUILD_DIR"

echo "Building universal Objective-C/AppKit binary for arm64 and x86_64..."
clang -ObjC -fobjc-arc -fblocks \
    -arch arm64 \
    -arch x86_64 \
    -mmacosx-version-min=13.0 \
    -isysroot "$SDK_PATH" \
    "$ROOT_DIR/Sources/CopyPaste/main.m" \
    -o "$UNIVERSAL_PRODUCT" \
    -framework Cocoa \
    -framework Carbon \
    -framework ApplicationServices

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$UNIVERSAL_PRODUCT" "$MACOS_DIR/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
find "$ROOT_DIR/Resources" -maxdepth 1 -type f ! -name "Info.plist" -exec cp {} "$RESOURCES_DIR/" \;
chmod +x "$MACOS_DIR/$APP_NAME"

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$APP_DIR" || true
fi

if command -v lipo >/dev/null 2>&1; then
    lipo -info "$MACOS_DIR/$APP_NAME"
fi

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR"
fi

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$APP_DIR" || true
fi

rm -f "$ZIP_PATH"
if command -v zip >/dev/null 2>&1; then
    (
        cd "$OUTPUT_DIR"
        COPYFILE_DISABLE=1 zip -qry --symlinks "$ZIP_PATH" "$APP_NAME.app"
    )
    echo "Created $ZIP_PATH"
elif command -v ditto >/dev/null 2>&1; then
    ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"
    echo "Created $ZIP_PATH"
fi

echo "Created $APP_DIR"

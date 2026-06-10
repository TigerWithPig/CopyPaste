#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CopyPaste"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-installer.dmg"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"

cd "$ROOT_DIR"

if ! command -v hdiutil >/dev/null 2>&1; then
    echo "hdiutil is required to create a DMG."
    exit 1
fi

"$ROOT_DIR/scripts/package-universal.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$STAGING_DIR/Trial Instructions.txt" <<EOF
CopyPaste trial build

Install:
1. Drag CopyPaste.app to Applications.
2. Open CopyPaste from Applications.
3. Grant Accessibility permission when prompted if you want auto paste.

Note:
This trial build is ad-hoc signed. macOS Gatekeeper may show an
"unidentified developer" warning on first launch.
EOF

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "Created $DMG_PATH"

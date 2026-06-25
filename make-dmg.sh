#!/bin/bash
# Build ClipHistory and package a drag-to-Applications .dmg.
#
# Usage:  ./make-dmg.sh [version]
# Output: ./ClipHistory-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-1.0}"
APP="ClipHistory.app"
VOL="ClipHistory"
DMG="ClipHistory-${VERSION}.dmg"

echo "[1/3] Building app..."
./build-app.sh >/dev/null

echo "[2/3] Staging disk image contents..."
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/$APP"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target

echo "[3/3] Creating ${DMG}..."
rm -f "$DMG"
hdiutil create \
    -volname "$VOL" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

echo "Built ${DMG} ($(du -h "$DMG" | cut -f1))"

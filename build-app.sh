#!/bin/bash
# Build ClipHistory and assemble a standalone ClipHistory.app bundle.
#
# Usage:  ./build-app.sh
# Output: ./ClipHistory.app   (drag to /Applications, or run `open ClipHistory.app`)
set -euo pipefail

cd "$(dirname "$0")"

APP="ClipHistory.app"
BIN_NAME="ClipHistory"

echo "[1/3] Compiling (release)..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${BIN_NAME}"

echo "[2/3] Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BIN_NAME}"
cp Info.plist "${APP}/Contents/Info.plist"

# Sign with the stable self-signed identity if present, so the Accessibility
# grant survives rebuilds (TCC keys on the cert, not the binary hash). Falls
# back to ad-hoc if the identity is missing (run ./setup-signing.sh to create it).
IDENTITY="ClipHistory Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "${IDENTITY}"; then
    echo "[3/3] Code signing with '${IDENTITY}'..."
    codesign --force --sign "${IDENTITY}" "${APP}"
else
    echo "[3/3] Code signing (ad-hoc -- run ./setup-signing.sh for a stable grant)..."
    codesign --force --sign - "${APP}" >/dev/null 2>&1 || true
fi

# If already installed in /Applications, refresh it in place. Same designated
# requirement (stable cert) -> the Accessibility grant carries over, no re-grant.
if [ -d "/Applications/${APP}" ]; then
    RUNNING=0
    pgrep -x "${BIN_NAME}" >/dev/null && RUNNING=1 && pkill -x "${BIN_NAME}" 2>/dev/null || true
    rm -rf "/Applications/${APP}"
    cp -R "${APP}" "/Applications/${APP}"
    echo "Updated /Applications/${APP} (Accessibility grant preserved)"
    if [ "${RUNNING}" -eq 1 ]; then
        open "/Applications/${APP}"
        echo "Relaunched."
    fi
else
    echo "Built ${APP}"
    echo "  Run it:     open ${APP}"
    echo "  Install it: cp -R ${APP} /Applications/"
fi

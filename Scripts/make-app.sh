#!/usr/bin/env bash
#
# Assemble a public-distribution `.app` bundle.
#
# Inputs (env vars, all optional):
#   DEV_ID          — Developer ID Application identity (e.g.
#                     "Developer ID Application: Jeff Alldridge (TEAMID)").
#                     When set, the app is signed with this identity and
#                     hardened runtime is enabled, ready for notarization.
#                     When unset, falls back to ad-hoc signing for local
#                     development.
#
# Output:
#   $1 — path to the .app bundle to assemble (e.g. build/macSubtitleOCR-gui.app)
#
# This bundle is intentionally MIT-licensed and slim:
#   - Contains our SwiftUI binary and the upstream `macSubtitleOCR` (MIT)
#   - Does NOT bundle MKVToolNix (GPL-2.0-or-later); users install it via
#     Homebrew at runtime. See THIRD_PARTY_LICENSES.md for rationale.
#
set -euo pipefail

APP="${1:?usage: make-app.sh <path/to/MyApp.app>}"
EXEC_NAME="macSubtitleOCR-gui"

APP_EXEC=".build/release/${EXEC_NAME}"
EMBEDDED_OCR="Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR"
INFO_PLIST="Resources/Info.plist"
ENTITLEMENTS="Resources/macSubtitleOCR-gui.entitlements"
ICON_SRC="Resources/icon.icon"
SVG_SRC="${ICON_SRC}/Assets/captions.bubble 2.svg"

for f in "$APP_EXEC" "$EMBEDDED_OCR" "$INFO_PLIST" "$ENTITLEMENTS" "$SVG_SRC"; do
    if [[ ! -e "$f" ]]; then
        echo "Error: missing $f. Run 'make build' first." >&2
        exit 1
    fi
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$APP_EXEC"     "$APP/Contents/MacOS/${EXEC_NAME}"
cp "$EMBEDDED_OCR" "$APP/Contents/Resources/macSubtitleOCR"
cp "$INFO_PLIST"   "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/${EXEC_NAME}"
chmod +x "$APP/Contents/Resources/macSubtitleOCR"

ICNS_DST="$APP/Contents/Resources/icon.icns"
echo "==> Building icon.icns from Icon Composer SVG"
swift Scripts/build-icns.swift "$SVG_SRC" "$ICNS_DST"
if [[ ! -s "$ICNS_DST" ]]; then
    echo "Error: icon.icns was not produced or is empty." >&2
    exit 1
fi

# Also ship the Icon Composer source for macOS 26+ Launch Services.
cp -R "$ICON_SRC" "$APP/Contents/Resources/icon.icon"

# --- Sign ---
# Production: Developer ID + hardened runtime + entitlements (notarization-ready)
# Dev: ad-hoc signing (local-only, won't notarize)
if [[ -n "${DEV_ID:-}" ]]; then
    echo "==> Signing with Developer ID + hardened runtime"
    SIGN_FLAGS=(--force --options runtime --timestamp
                --entitlements "$ENTITLEMENTS"
                --sign "$DEV_ID")

    # Sign nested binaries first (they get sealed into the outer signature)
    codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Resources/macSubtitleOCR"
    codesign "${SIGN_FLAGS[@]}" "$APP/Contents/MacOS/${EXEC_NAME}"
    codesign "${SIGN_FLAGS[@]}" "$APP"
else
    echo "==> Signing ad-hoc (local dev; set DEV_ID for notarization-ready build)"
    codesign --force --sign - "$APP/Contents/Resources/macSubtitleOCR"
    codesign --force --sign - "$APP/Contents/MacOS/${EXEC_NAME}"
    codesign --force --sign - "$APP"
fi

# --- Verify ---
echo "==> Verifying bundle"
codesign --verify --verbose=1 "$APP" >/dev/null
spctl --assess --type execute --verbose=1 "$APP" 2>&1 | head -1 || true

size=$(du -sh "$APP" | awk '{print $1}')
echo "==> Built $APP ($size)"

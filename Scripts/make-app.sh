#!/usr/bin/env bash
#
# Assemble the distributable `.app` bundle.
#
# The app is entirely self-contained: one universal Mach-O executable, an
# icon, and an Info.plist. Nothing is shelled out to at runtime, so there is
# no dylib relocation, no embedded CLI, and no Homebrew dependency.
#
# Inputs (environment):
#   DEV_ID  Developer ID Application identity, e.g.
#           "Developer ID Application: Jeff Alldridge (TEAMID)". When set, the
#           bundle is signed with a hardened runtime, ready for notarization.
#           When unset, it is ad-hoc signed for local use.
#
# Usage:
#   Scripts/make-app.sh build/macSubtitleOCR-gui.app
#
set -euo pipefail

APP="${1:?usage: make-app.sh <path/to/MyApp.app>}"
EXEC_NAME="macSubtitleOCR-gui"

BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP_EXEC="${BIN_DIR}/${EXEC_NAME}"
INFO_PLIST="Resources/Info.plist"
ENTITLEMENTS="Resources/macSubtitleOCR-gui.entitlements"
ICON_SRC="Resources/AppIcon.icon"

for f in "$APP_EXEC" "$INFO_PLIST" "$ENTITLEMENTS" "$ICON_SRC"; do
    if [[ ! -e "$f" ]]; then
        echo "Error: missing $f. Run 'make build' first." >&2
        exit 1
    fi
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$APP_EXEC"   "$APP/Contents/MacOS/${EXEC_NAME}"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/${EXEC_NAME}"

# --- Universal check ---
# A single-architecture build still runs on the build machine, so this would
# otherwise only surface when an Intel user opens the release.
archs="$(lipo -archs "$APP/Contents/MacOS/${EXEC_NAME}")"
echo "==> Executable architectures: $archs"
for want in arm64 x86_64; do
    if [[ "$archs" != *"$want"* ]]; then
        echo "Error: the executable is missing the $want slice (got: $archs)." >&2
        echo "       Build with: swift build -c release --arch arm64 --arch x86_64" >&2
        exit 1
    fi
done

# --- Icon ---
# Icon Composer sources compile to an Assets.car (Liquid Glass on macOS 26)
# plus a classic .icns for everything older.
echo "==> Compiling $ICON_SRC"
ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT
xcrun actool "$ICON_SRC" \
    --compile "$ICON_TMP" \
    --platform macosx \
    --minimum-deployment-target 15.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_TMP/partial.plist" \
    --output-format human-readable-text >/dev/null

for asset in Assets.car AppIcon.icns; do
    if [[ ! -s "$ICON_TMP/$asset" ]]; then
        echo "Error: actool did not produce $asset." >&2
        exit 1
    fi
    cp "$ICON_TMP/$asset" "$APP/Contents/Resources/$asset"
done
rm -rf "$ICON_TMP"
trap - EXIT

# --- Sign ---
if [[ -n "${DEV_ID:-}" ]]; then
    echo "==> Signing with Developer ID + hardened runtime"
    codesign --force --options runtime --timestamp \
             --entitlements "$ENTITLEMENTS" \
             --sign "$DEV_ID" "$APP"
else
    echo "==> Signing ad-hoc (local dev; set DEV_ID for a notarization-ready build)"
    codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=1 "$APP" >/dev/null

if [[ -n "${DEV_ID:-}" ]]; then
    # Gatekeeper rejects a Developer ID app that has not been notarized yet,
    # which is the expected state here — notarization happens next, in
    # `make notarize`. Report the verdict but never fail on it.
    echo "==> Gatekeeper assessment (pre-notarization, informational)"
    spctl --assess --type execute --verbose=1 "$APP" 2>&1 | head -1 || true
fi

# --- Self-check ---
# Runs the assembled bundle to confirm it is complete: Info.plist keys, icon
# assets, and a real decode through the engine. Packaging bugs do not show up
# in unit tests, which run inside the build tree.
echo "==> Self-check"
"$APP/Contents/MacOS/${EXEC_NAME}" --self-check

size=$(du -sh "$APP" | awk '{print $1}')
echo "==> Built $APP ($size, $archs)"

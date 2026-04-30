#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: make-app.sh <path/to/MyApp.app>}"
EXEC_NAME="macSubtitleOCR-gui"

# --- Preflight ---
need() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: $1 is required to assemble the .app." >&2
        echo "$2" >&2
        exit 1
    fi
}

need dylibbundler "Install with: brew install dylibbundler"
need mkvmerge     "Install with: brew install mkvtoolnix"
need mkvextract   "Install with: brew install mkvtoolnix"

# Resolve any symlinks on the brew-installed binaries so we copy real Mach-O files
resolve() {
    local path="$1"
    # `realpath` is available on Tahoe / modern macOS; fall back to python if needed
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path"
    else
        python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$path"
    fi
}

MKVMERGE_REAL="$(resolve "$(command -v mkvmerge)")"
MKVEXTRACT_REAL="$(resolve "$(command -v mkvextract)")"
APP_EXEC="./.build/release/${EXEC_NAME}"
EMBEDDED_OCR="./Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR"
INFO_PLIST="./Resources/Info.plist"

for f in "$APP_EXEC" "$EMBEDDED_OCR" "$INFO_PLIST"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: missing $f. Run 'make build' first." >&2
        exit 1
    fi
done

# --- Assemble bundle skeleton ---
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"

cp "$APP_EXEC"     "$APP/Contents/MacOS/${EXEC_NAME}"
cp "$EMBEDDED_OCR" "$APP/Contents/Resources/macSubtitleOCR"
cp "$MKVMERGE_REAL"   "$APP/Contents/Resources/mkvmerge"
cp "$MKVEXTRACT_REAL" "$APP/Contents/Resources/mkvextract"
cp "$INFO_PLIST"   "$APP/Contents/Info.plist"

chmod +x "$APP/Contents/MacOS/${EXEC_NAME}"
chmod +x "$APP/Contents/Resources/macSubtitleOCR"
chmod +x "$APP/Contents/Resources/mkvmerge"
chmod +x "$APP/Contents/Resources/mkvextract"

# --- Bundle flat dylibs ---
# dylibbundler walks the load commands of each executable, copies any
# /opt/homebrew/... or /usr/local/... dylib it depends on into Frameworks/,
# rewrites the install names to @executable_path/../Frameworks/<lib>, and
# recurses so transitive deps get picked up too.
# NOTE: dylibbundler does not handle .framework bundles; those are handled below.
echo "==> Bundling flat dylibs (dylibbundler)"
dylibbundler \
    -od -b -ns \
    -x "$APP/Contents/Resources/mkvmerge" \
    -x "$APP/Contents/Resources/mkvextract" \
    -d "$APP/Contents/Frameworks/" \
    -p "@executable_path/../Frameworks/"

# --- Bundle Qt frameworks ---
# mkvmerge/mkvextract link against QtCore.framework which dylibbundler skips
# because it uses the Mach-O .framework bundle layout rather than a flat dylib.
# Strategy:
#   1. Copy QtCore.framework into Contents/Frameworks/
#   2. Rewrite the -id and all internal homebrew deps of the framework binary
#   3. Rewrite the framework reference in mkvmerge/mkvextract
#   4. Copy and rewrite any flat dylibs that QtCore itself depends on
echo "==> Bundling Qt frameworks"

FW_DIR="$APP/Contents/Frameworks"

# Collect all framework deps from the mkv binaries into a temp file (avoid subshells)
TMPFW=$(mktemp)
trap 'rm -f "$TMPFW"' EXIT

for bin in "$APP/Contents/Resources/mkvmerge" "$APP/Contents/Resources/mkvextract"; do
    otool -L "$bin" | tail -n +2 | awk '{print $1}' | grep -E '^/opt/homebrew/.*\.framework/' >> "$TMPFW" || true
done
sort -u "$TMPFW" -o "$TMPFW"

if [[ -s "$TMPFW" ]]; then
    while IFS= read -r dep; do
        # Extract framework name: /opt/homebrew/opt/qtbase/lib/QtCore.framework/... -> QtCore
        fw_name="$(echo "$dep" | sed -E 's|.*/([^/]+)\.framework/.*|\1|')"
        # Extract source lib dir: /opt/homebrew/opt/qtbase/lib
        fw_src_dir="$(echo "$dep" | sed -E "s|/${fw_name}\\.framework.*||")"
        fw_src="${fw_src_dir}/${fw_name}.framework"
        fw_dst="${FW_DIR}/${fw_name}.framework"

        if [[ ! -d "$fw_dst" ]]; then
            echo "  Copying ${fw_name}.framework"
            cp -R "$fw_src" "$fw_dst"
            # Remove code signature — invalidated by install_name_tool anyway
            rm -rf "$fw_dst/Versions/A/_CodeSignature" 2>/dev/null || true

            fw_binary="${fw_dst}/Versions/A/${fw_name}"
            chmod +w "$fw_binary"

            # Rewrite the framework's own -id
            new_id="@executable_path/../Frameworks/${fw_name}.framework/Versions/A/${fw_name}"
            install_name_tool -id "$new_id" "$fw_binary" 2>/dev/null || true

            # Collect and rewrite flat homebrew dylib deps inside this framework binary
            TMPFWDEPS=$(mktemp)
            otool -L "$fw_binary" | tail -n +2 | awk '{print $1}' \
                | grep -E '^(/opt/homebrew|/usr/local)/.*\.dylib$' > "$TMPFWDEPS" || true
            while IFS= read -r fw_dep; do
                dep_base="$(basename "$fw_dep")"
                dep_dst="${FW_DIR}/${dep_base}"
                if [[ ! -f "$dep_dst" ]]; then
                    echo "    Copying transitive flat dep: $dep_base"
                    dep_real="$(resolve "$fw_dep")"
                    cp "$dep_real" "$dep_dst"
                    chmod +w "$dep_dst"
                    install_name_tool -id "@executable_path/../Frameworks/${dep_base}" "$dep_dst" 2>/dev/null || true
                fi
                install_name_tool -change "$fw_dep" "@executable_path/../Frameworks/${dep_base}" "$fw_binary" 2>/dev/null || true
            done < "$TMPFWDEPS"
            rm -f "$TMPFWDEPS"
        fi

        # Rewrite the reference in the mkv binaries
        new_ref="@executable_path/../Frameworks/${fw_name}.framework/Versions/A/${fw_name}"
        for bin in "$APP/Contents/Resources/mkvmerge" "$APP/Contents/Resources/mkvextract"; do
            install_name_tool -change "$dep" "$new_ref" "$bin" 2>/dev/null || true
        done
    done < "$TMPFW"
fi

# --- Fix up transitive flat deps of the newly-added framework flat deps ---
# Some flat deps (e.g. libglib) may themselves have further homebrew deps.
# Walk Frameworks/ flat dylibs and fix any remaining homebrew references.
echo "==> Fixing transitive deps in Frameworks/"
changed=1
iterations=0
while [[ $changed -eq 1 && $iterations -lt 10 ]]; do
    changed=0
    iterations=$((iterations + 1))
    for lib in "$FW_DIR"/*.dylib; do
        [[ -f "$lib" ]] || continue
        TMPDEPS=$(mktemp)
        otool -L "$lib" | tail -n +2 | awk '{print $1}' \
            | grep -E '^(/opt/homebrew|/usr/local)/.*\.dylib$' > "$TMPDEPS" || true
        while IFS= read -r dep; do
            dep_base="$(basename "$dep")"
            dep_dst="${FW_DIR}/${dep_base}"
            if [[ ! -f "$dep_dst" ]]; then
                echo "    Copying: $dep_base"
                dep_real="$(resolve "$dep")"
                cp "$dep_real" "$dep_dst"
                chmod +w "$dep_dst"
                install_name_tool -id "@executable_path/../Frameworks/${dep_base}" "$dep_dst" 2>/dev/null || true
                changed=1
            fi
            install_name_tool -change "$dep" "@executable_path/../Frameworks/${dep_base}" "$lib" 2>/dev/null || true
        done < "$TMPDEPS"
        rm -f "$TMPDEPS"
    done
done

# --- Deduplicate rpaths ---
# dylibbundler adds @executable_path/../Frameworks/ as an LC_RPATH. If the original
# binary already contained that rpath, macOS dyld will abort with "duplicate LC_RPATH".
# Remove all copies of the rpath then add exactly one back.
echo "==> Deduplicating rpaths"
dedup_rpath() {
    local bin="$1"
    local rpath="@executable_path/../Frameworks/"
    # Count occurrences
    local count
    count=$(otool -l "$bin" | grep -c "path ${rpath}" || true)
    # Remove all copies (install_name_tool -delete_rpath fails if rpath absent, so guard)
    local i
    for ((i = 0; i < count; i++)); do
        install_name_tool -delete_rpath "$rpath" "$bin" 2>/dev/null || true
    done
    # Add exactly one
    install_name_tool -add_rpath "$rpath" "$bin" 2>/dev/null || true
}
dedup_rpath "$APP/Contents/Resources/mkvmerge"
dedup_rpath "$APP/Contents/Resources/mkvextract"

# --- Ad-hoc codesign all modified binaries ---
# install_name_tool invalidates existing code signatures. macOS (from Ventura onward)
# kills unsigned or signature-mismatched binaries with SIGKILL. Ad-hoc signing ("-")
# marks the binary as self-signed, which satisfies the kernel's code-signing check
# without requiring an Apple Developer certificate.
echo "==> Ad-hoc codesigning binaries"
adhoc_sign() {
    local bin="$1"
    codesign --force --sign - "$bin" 2>/dev/null || true
}

adhoc_sign "$APP/Contents/Resources/mkvmerge"
adhoc_sign "$APP/Contents/Resources/mkvextract"
adhoc_sign "$APP/Contents/Resources/macSubtitleOCR"
adhoc_sign "$APP/Contents/MacOS/${EXEC_NAME}"

for fw_binary in "$FW_DIR"/*.framework/Versions/A/*; do
    [[ -f "$fw_binary" ]] || continue
    adhoc_sign "$fw_binary"
done

for lib in "$FW_DIR"/*.dylib; do
    [[ -f "$lib" ]] || continue
    adhoc_sign "$lib"
done

# --- Sanity check ---
echo "==> Verifying bundle"
verify() {
    local bin="$1"
    local bad
    bad=$(otool -L "$bin" | tail -n +2 | awk '{print $1}' | grep -E '^(/opt/homebrew|/usr/local)' || true)
    if [[ -n "$bad" ]]; then
        echo "Error: $bin still references external dylibs:" >&2
        echo "$bad" >&2
        exit 1
    fi
}
verify "$APP/Contents/Resources/mkvmerge"
verify "$APP/Contents/Resources/mkvextract"

for fw_binary in "$FW_DIR"/*.framework/Versions/A/*; do
    [[ -f "$fw_binary" ]] || continue
    verify "$fw_binary"
done

# Report size
size=$(du -sh "$APP" | awk '{print $1}')
echo "==> Built $APP ($size)"

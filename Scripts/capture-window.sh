#!/usr/bin/env bash
#
# Capture the running app's window as a transparent PNG — window plus its
# shadow, with nothing of the desktop behind it. This is the scriptable
# equivalent of ⇧⌘4 then Space then clicking the window.
#
# Region capture (`screencapture -R x,y,w,h`) is NOT equivalent: it grabs a
# flat rectangle, so whatever sits behind the window's rounded corners bleeds
# into the image and there is no alpha channel.
#
# Usage:
#   Scripts/capture-window.sh docs/screenshots/main-window.png
#   Scripts/capture-window.sh out.png "sintel"          # match window title
#   Scripts/capture-window.sh out.png "sintel" "macSubtitleOCR"
#
# The app must already be running. Note the window's *owner* name is the
# bundle display name (macSubtitleOCR), not the executable (macSubtitleOCR-gui).
#
# Pass a title substring whenever the app might also have an Open/Save panel
# on screen — those panels belong to the same process, and capturing one by
# accident can leak the contents of your Finder sidebar into a public image.
set -euo pipefail

OUT="${1:?usage: capture-window.sh <output.png> [title-substring] [app-display-name]}"
TITLE="${2:-}"
APP="${3:-macSubtitleOCR}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/winid.swift" <<'SWIFT'
import CoreGraphics
import Foundation

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let titleNeedle = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

// Titles of the standard AppKit panels that share our process. Capturing one
// of these would put the user's Finder sidebar into a screenshot.
let panelTitles: Set<String> = ["Open", "Save", "Print", "Page Setup"]

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("could not read the window list\n".utf8))
    exit(1)
}

for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let name = window[kCGWindowName as String] as? String ?? ""
    let layer = window[kCGWindowLayer as String] as? Int ?? -1
    let number = window[kCGWindowNumber as String] as? Int ?? 0
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let height = bounds["Height"] as? Double ?? 0

    guard owner == target, layer == 0, height > 200 else { continue }
    guard !panelTitles.contains(name) else { continue }
    guard !name.isEmpty else { continue }
    if !titleNeedle.isEmpty, !name.contains(titleNeedle) { continue }

    // stderr, so stdout stays machine-parseable as "<windowID> <pid>"
    let pid = window[kCGWindowOwnerPID as String] as? Int ?? 0
    FileHandle.standardError.write(Data("matched window \"\(name)\"\n".utf8))
    print("\(number) \(pid)")
    exit(0)
}

FileHandle.standardError.write(
    Data("no on-screen window for \"\(target)\"\(titleNeedle.isEmpty ? "" : " titled ~\"\(titleNeedle)\"")\n".utf8))
exit(2)
SWIFT

read -r WID PID <<<"$(swift "$WORK/winid.swift" "$APP" "$TITLE")"

# Bring the window forward so the capture shows active chrome (coloured
# traffic lights) rather than the dimmed inactive state. Target the owning
# pid: the window's owner name, the process name, and the AppleScript
# application name are all different here, so activating by name is fragile.
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $PID) to true" \
    >/dev/null 2>&1 || true
sleep 1.5

screencapture -x -l"$WID" "$OUT"

if ! sips -g hasAlpha "$OUT" 2>/dev/null | grep -q "hasAlpha: yes"; then
    echo "Error: $OUT has no alpha channel; expected a window capture." >&2
    exit 1
fi

echo "==> Wrote $OUT ($(sips -g pixelWidth -g pixelHeight "$OUT" | awk '/pixel/{printf "%s ", $2}')px, transparent)"

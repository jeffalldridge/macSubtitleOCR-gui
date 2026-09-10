#!/usr/bin/env bash
#
# Diff the vendored engine against upstream macSubtitleOCR.
#
# `Sources/SubtitleEngine/` is a port, not a copy: it was restructured for
# in-process use, random-access decoding, progress, and cancellation. This
# script does not produce an applyable patch — it shows what upstream has
# changed in the decoders since the recorded commit, so a maintainer can
# decide what is worth merging by hand.
#
# Usage:
#   Scripts/diff-upstream.sh            # against upstream main
#   Scripts/diff-upstream.sh v1.1.0     # against a tag or commit
#
set -euo pipefail

REF="${1:-main}"
UPSTREAM_URL="https://github.com/ecdye/macSubtitleOCR.git"
RECORDED_SHA="$(grep -oE '`[0-9a-f]{40}`' Sources/SubtitleEngine/UPSTREAM.md | head -1 | tr -d '`')"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Cloning $UPSTREAM_URL"
git clone --quiet --filter=blob:none "$UPSTREAM_URL" "$WORK/upstream"
git -C "$WORK/upstream" checkout --quiet "$REF"
NEW_SHA="$(git -C "$WORK/upstream" rev-parse HEAD)"

echo "==> Ported from: ${RECORDED_SHA:-unknown}"
echo "==> Comparing to: $NEW_SHA ($REF)"
echo

if [[ -n "$RECORDED_SHA" && "$RECORDED_SHA" == "$NEW_SHA" ]]; then
    echo "Up to date: upstream $REF is the commit this port is based on."
    exit 0
fi

if [[ -n "$RECORDED_SHA" ]]; then
    echo "==> Upstream changes to the decoder sources since the port"
    echo
    git -C "$WORK/upstream" --no-pager diff --stat "$RECORDED_SHA" "$NEW_SHA" -- \
        Sources/macSubtitleOCR/MKV \
        Sources/macSubtitleOCR/Subtitles \
        Sources/macSubtitleOCR/Extensions || true
    echo
    echo "==> Full diff"
    echo
    git -C "$WORK/upstream" --no-pager diff "$RECORDED_SHA" "$NEW_SHA" -- \
        Sources/macSubtitleOCR/MKV \
        Sources/macSubtitleOCR/Subtitles \
        Sources/macSubtitleOCR/Extensions || true
else
    echo "No upstream commit recorded in Sources/SubtitleEngine/UPSTREAM.md." >&2
    exit 1
fi

echo
echo "After merging anything, update the commit recorded in Sources/SubtitleEngine/UPSTREAM.md."

# Claude instructions for macSubtitleOCR-gui

## Project shape

SwiftUI macOS app driven by SwiftPM. The upstream `macSubtitleOCR` CLI is vendored
as a git submodule under `Vendor/macSubtitleOCR` and built by the Makefile, which
drops the resulting binary into `Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR`
before invoking `swift build` on the GUI.

**Always use `make build` (or `make run` / `make app`), never `swift build` directly** —
otherwise the bundled binary will be missing.

## Tests

`swift test` runs Swift Testing suites in `Tests/macSubtitleOCR-guiTests/`. Pure
components (TrackProber, MKVToolNixExtractor, OCRRunner, SRTFinalizer) are TDD'd.
SwiftUI views are not snapshot-tested in v1.

## Updating upstream macSubtitleOCR

`make update` runs `git submodule update --remote` and rebuilds. Commit the bumped
submodule SHA after testing.

## Spec / plan

See `docs/superpowers/specs/2026-04-30-macSubtitleOCR-gui-design.md` and
`docs/superpowers/plans/2026-04-30-macSubtitleOCR-gui.md`.

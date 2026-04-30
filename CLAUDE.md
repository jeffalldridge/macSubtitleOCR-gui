# Claude instructions for macSubtitleOCR-gui

## What this project is

A SwiftUI macOS app that wraps the upstream `macSubtitleOCR` CLI. The upstream
tool is vendored as a git submodule at `Vendor/macSubtitleOCR/`. The Makefile
builds it and copies the resulting binary into
`Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR` before invoking
`swift build` on the GUI.

The shipped `.app` is **fully self-contained**: `make app` also copies brew's
`mkvmerge` / `mkvextract` into the bundle, then runs `dylibbundler` (plus a
manual Qt-framework relocation pass and a re-codesign pass) so all dylibs live
under `Contents/Frameworks/` with `@executable_path/../Frameworks/` install
names. No `brew install mkvtoolnix` is required on the target machine.

## Build hygiene

- **Always use `make build` / `make run` / `make app`.** Never run `swift build`
  directly without first running `make build` — the binary at
  `Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR` is gitignored and won't
  exist on a fresh clone until the Makefile produces it.
- The first `make build` is slow because it compiles `macSubtitleOCR` from source.
- `make clean` wipes everything, including the embedded binary and the assembled `.app`.
- `make app` requires `dylibbundler` and `mkvtoolnix` on the BUILD machine
  (the user-facing app doesn't need them).

## Tests

`swift test` runs Swift Testing (`import Testing`) suites in
`Tests/macSubtitleOCR-guiTests/`. Pure components (TrackProber,
MKVToolNixExtractor, OCRRunner, SRTFinalizer, SubtitleJob, BundledBinary,
ToolchainProbe) are TDD'd with real assertions. SwiftUI views are not
snapshot-tested in v1.

## Updating upstream macSubtitleOCR

`make update` runs `git submodule update --remote` and rebuilds. After
verifying the new build works, commit the bumped submodule SHA. Don't bump it
without testing — upstream may change its CLI surface.

## Project layout

- `Sources/macSubtitleOCR-gui/Probing/` — TrackProber, ToolchainProbe, Track
- `Sources/macSubtitleOCR-gui/Extraction/` — TrackExtractor protocol + mkvextract impl
- `Sources/macSubtitleOCR-gui/OCR/` — OCRRunner, OCRPipeline, BundledBinary
- `Sources/macSubtitleOCR-gui/Finalize/` — SRTFinalizer
- `Sources/macSubtitleOCR-gui/Views/` — DropView, TracksView, RunView, DoneView
- `Sources/macSubtitleOCR-gui/SubtitleJob.swift` — single source of truth
- `Scripts/make-app.sh` — `.app` bundle assembly + dylib relocation + codesigning

## Spec / plan

See `docs/superpowers/specs/2026-04-30-macSubtitleOCR-gui-design.md` and
`docs/superpowers/plans/2026-04-30-macSubtitleOCR-gui.md`.

## When working on this codebase

- The track-extraction step lives behind a `TrackExtractor` protocol so we can
  swap to a future upstream `--track` flag without rewriting the pipeline.
- `ToolchainProbe.mkvtoolnix()` checks `Bundle.main` resources first (production
  `.app`) and falls back to PATH + Homebrew (dev mode).
- `BundledBinary.resolve()` looks in (1) the `.app` bundle, (2) `Bundle.module`,
  (3) adjacent to the executable, (4) the vendored submodule build dir. Adding a
  new lookup location requires updating both `bundledPaths()` and the tests.
- Filenames use `Movie.<iso639>.srt`, with `-1`, `-2`, … suffixes on conflict.
  See `SRTFinalizer.targetURL`.
- `make-app.sh` does three non-obvious things after copying binaries:
  (1) dylibbundler for normal dylibs, (2) manual relocation of `QtCore.framework`
  because dylibbundler skips `.framework` bundles, (3) ad-hoc codesign of every
  modified Mach-O *plus* the outer `.app` bundle, because `install_name_tool`
  invalidates signatures and macOS will SIGKILL unsigned binaries.

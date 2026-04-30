# macSubtitleOCR-gui — Design Spec

**Date:** 2026-04-30
**Status:** Approved (brainstorming complete)
**Author:** Jeff Alldridge + Claude

## Purpose

A small, polished macOS SwiftUI app that wraps the [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR) CLI tool. One job: take a video or subtitle file with PGS or VobSub data, let the user pick a single track, produce a clean SRT next to the original file. Designed for a Subler-based muxing workflow where the SRT will be soft-muxed into an MP4 downstream.

## Scope

**In scope:**

- Drag-and-drop file input for `.mkv`, `.mks`, `.sup`, `.sub`/`.idx`
- Listing PGS and VobSub tracks inside MKVs and selecting exactly one
- Running OCR on the selected track only
- Live progress UI with a cancellable run
- Clean SRT output written next to the input
- Configurable OCR language (default `en`)
- Reproducible build via a vendored macSubtitleOCR submodule
- One-command "get the latest" upstream tool

**Out of scope (v1):**

- MP4 input (PGS-in-MP4 is essentially never seen)
- Batch processing (folder drop, multiple files)
- Code signing / notarization / Mac App Store
- Sparkle auto-update of the GUI itself
- Forking macSubtitleOCR to add native `--track` flag (noted as future work)
- ffmpeg dependency

## Architecture

Six single-responsibility components communicating through a shared observable state object.

### Components

- **`AppView`** — root SwiftUI view. Routes between `Drop → Tracks → Progress → Done` based on `SubtitleJob.phase`.
- **`SubtitleJob`** — `@Observable` state container. Holds: input URL, detected tracks, selected track, OCR options, current phase, progress fraction, log lines, final SRT URL, error. Single source of truth for the UI.
- **`TrackProber`** — given an input URL, returns `[Track]`. For MKVs, shells out to `mkvmerge -J` and parses JSON. For `.sup` and `.sub`/`.idx`, returns a synthetic single-element list.
- **`TrackExtractor`** (protocol) — given an MKV URL and track number, writes a temp `.sup` to disk and returns its URL. Default impl: `MKVToolNixExtractor` shells out to `mkvextract`. Lives behind a protocol so a future `--track`-aware macSubtitleOCR can replace this step entirely.
- **`OCRRunner`** — given a `.sup` (or `.sub`/`.idx` pair) plus options, invokes the bundled macSubtitleOCR binary via `Process`. Streams stdout/stderr, posts log lines and progress to `SubtitleJob`. Async/await, cancellable.
- **`SRTFinalizer`** — moves the produced SRT next to the original input under a clean filename (`<input-basename>.<lang>.srt`), handles filename conflicts (suffix `-1`, `-2`, …), removes temp files.

### Data flow

```
DropView → SubtitleJob.input
  → TrackProber → SubtitleJob.tracks
TracksView → SubtitleJob.selectedTrack + OCR options
  → TrackExtractor (if MKV) → temp .sup
  → OCRRunner → temp output dir, streams progress/log
  → SRTFinalizer → final SRT next to input
DoneView ← SubtitleJob.outputURL
```

## User Flow

1. **Drop** screen — large drop zone, "Drop a `.mkv`, `.sup`, `.sub`, or `.idx` file" + "Choose file…" button. mkvtoolnix presence is checked here; missing-deps banner blocks progression.
2. **Tracks** screen (only shown when input is MKV with ≥2 PGS/VobSub tracks; auto-skipped otherwise) — list of tracks with codec, ISO 639 language code, optional track name. Single-select. Disclosure section: language for OCR (default `en`), invert flag, custom words, disable-I-correction toggle.
3. **Progress** screen — current phase string, elapsed time, progress bar (determinate where possible, indeterminate otherwise), Cancel button. Collapsed log panel showing tool stderr.
4. **Done** screen — "✓ Saved `MyMovie.en.srt`" with **Reveal in Finder** + **OCR another** + **Quit**.

Errors land in the same screen with the failure reason, the log, and **Try again** / **Open another file**.

## Project Layout

```
macSubtitleOCR-gui/
  Package.swift
  Makefile
  README.md
  CLAUDE.md
  .gitignore
  .gitmodules
  Vendor/
    macSubtitleOCR/                  # git submodule
  Sources/
    macSubtitleOCR-gui/
      App.swift                      # @main, App + WindowGroup
      AppView.swift
      SubtitleJob.swift
      Probing/
        TrackProber.swift
        Track.swift
      Extraction/
        TrackExtractor.swift         # protocol
        MKVToolNixExtractor.swift    # default impl
      OCR/
        OCRRunner.swift
        BundledBinary.swift          # locates the embedded macSubtitleOCR
      Finalize/
        SRTFinalizer.swift
      Views/
        DropView.swift
        TracksView.swift
        ProgressView.swift
        DoneView.swift
      Resources/
        macSubtitleOCR               # compiled binary, dropped here by Makefile
  Tests/
    macSubtitleOCR-guiTests/
  docs/
    superpowers/specs/
      2026-04-30-macSubtitleOCR-gui-design.md
```

## Build + Update Mechanism

`Makefile` targets:

- `make build` — `git submodule update --init --recursive`; `swift build -c release` in `Vendor/macSubtitleOCR`; copy the resulting binary into `Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR`; `swift build -c release` in the root package.
- `make app` — runs `make build`, then assembles a real `.app` bundle (`Contents/Info.plist`, `Contents/MacOS/macSubtitleOCR-gui`, `Contents/Resources/macSubtitleOCR`). Output: `build/macSubtitleOCR-gui.app`. This is what gets dragged to `/Applications`.
- `make run` — `make build`, then runs the executable directly (fastest dev loop).
- `make update` — `git -C Vendor/macSubtitleOCR fetch && git -C Vendor/macSubtitleOCR checkout origin/main`; `make build`. Leaves the bumped submodule SHA staged so you can commit it. Prints the upstream commit range so you can read what changed.
- `make clean` — wipes `.build/`, embedded binary, and the assembled `.app`.

At runtime the GUI resolves the binary via `Bundle.main.url(forResource: "macSubtitleOCR", withExtension: nil, subdirectory: nil)` (it's at the bundle's `Contents/Resources/macSubtitleOCR`). Missing binary surfaces a clear "run `make build`" message — only ever hits during dev.

## Error Handling

- **MKVToolNix missing** — at app launch, `BundledBinary` and a `ToolchainProbe` check for `mkvmerge` and `mkvextract` on `PATH`, in `/opt/homebrew/bin`, and in `/usr/local/bin`. If missing, the Drop screen shows a banner: "macSubtitleOCR-gui needs MKVToolNix" with the exact `brew install mkvtoolnix` command and a Copy button. Never auto-runs brew. Re-probes when the user clicks "I installed it."
- **Bundled binary missing** — clear error pointing at the expected path with `make build` instructions.
- **Underlying tool failure** — full stderr captured, surfaced in the log panel. Common cases get friendlier copy: "No PGS or VobSub tracks found in this file," "OCR returned 0 cues — the track may be empty."
- **Cancellation** — the OCR `Process` is sent `SIGTERM`; temp dir is removed; UI returns to the previous screen.

## Testing Strategy

- **Unit:** `TrackProber` against fixture JSON from `mkvmerge -J`.
- **Unit:** `MKVToolNixExtractor` argument construction (pure function — no `Process`).
- **Unit:** `OCRRunner` argument construction.
- **Unit:** `SRTFinalizer` filename rules (`.mkv` → `.<lang>.srt`, conflict suffixing, edge cases).
- **Manual:** README-documented smoke-test plan with a known-good `.mkv` fixture (drop → pick track → verify SRT cues are reasonable).
- No SwiftUI snapshot tests in v1.

## Open Questions / Future Work

- Contribute `--track <n>` to macSubtitleOCR upstream. Collapses extraction into the binary and removes the mkvtoolnix runtime dependency.
- Batch mode (drop a folder, queue files).
- Sparkle for self-update of the GUI itself.
- Code signing + notarization for sharing builds.
- Optional MP4 input via ffmpeg extraction (extremely rare in practice).

## Decisions Locked

| # | Decision | Choice |
|---|---|---|
| 1 | Input formats | MKV, SUP, SUB/IDX (no MP4, no ffmpeg) |
| 2 | Track selection | mkvtoolnix probe + extract; behind a protocol so we can swap to a future `--track` flag |
| 3 | UI tech | SwiftUI macOS app, SwiftPM-driven, no `.xcodeproj` |
| 4 | Update mechanism | macSubtitleOCR as a git submodule under `Vendor/`; `make update` |
| 5 | Repo name | `macSubtitleOCR-gui` |

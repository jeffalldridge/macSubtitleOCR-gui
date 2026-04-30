# macSubtitleOCR-gui

A polished macOS SwiftUI front-end for [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR).
Drop a `.mkv`, `.sup`, `.sub`, or `.idx` file, pick one or more PGS / VobSub
tracks, and get clean `.srt` files next to your source. Designed for muxing
into MP4 soft-subs with [Subler](https://subler.org).

By Jeff Alldridge / [Tent Studios, LLC](https://tentstudios.com). The
underlying OCR engine is [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR)
by Ethan Dye, MIT-licensed.

## Why

`macSubtitleOCR` is the best macOS-native PGS-to-SRT tool there is, but its CLI
OCRs *every* subtitle track in an MKV — rarely what you want when you're cutting
a single language for a release. This GUI lets you pick exactly one track, runs
the OCR with a progress UI, and writes the SRT next to your source under a clean
`<MovieName>.<lang>.srt` filename.

## Distribution

The shipped `.app` is self-contained: macSubtitleOCR, `mkvmerge`, `mkvextract`,
and all their dylibs (Qt, Boost, libebml, libmatroska, etc.) live inside
`Contents/Resources` and `Contents/Frameworks`. **No `brew install` needed on the
target machine.** Just drag the `.app` into `/Applications` and run.

The bundle is ad-hoc code-signed (no Apple Developer ID), so the first launch
needs a right-click → Open to bypass Gatekeeper.

## Build requirements

To **build** the .app yourself you need:

- macOS 14 or newer
- Swift 6 toolchain (Xcode 16+ command-line tools, or [Swift.org toolchain](https://swift.org/download/))
- [MKVToolNix](https://mkvtoolnix.download): `brew install mkvtoolnix` (binaries are copied into the .app)
- [dylibbundler](https://github.com/auriamg/macdylibbundler): `brew install dylibbundler` (used by `make app` to relocate dylibs)

End users of the built `.app` need none of these.

## Commands

```sh
make build      # compiles the vendored macSubtitleOCR + this app
make run        # builds and runs straight from the terminal (dev mode)
make app        # assembles build/macSubtitleOCR-gui.app — drag to /Applications
make test       # runs the Swift Testing suites
make clean      # wipes build artifacts
```

The first `make build` is slow (it compiles `macSubtitleOCR` from source).
Subsequent builds reuse the cache.

## Update upstream macSubtitleOCR

```sh
make update     # bumps the submodule to upstream/main and rebuilds
```

After verifying the new build works, commit the bumped submodule SHA:

```sh
git add Vendor/macSubtitleOCR
git commit -m "Bump macSubtitleOCR to <upstream-sha>"
```

## Workflow

1. Drop a video / subtitle file into the window.
2. If it's an MKV with multiple PGS/VobSub tracks, pick the one you want.
3. (Optional) tweak language code, invert flag, custom words.
4. Click **Run OCR**. Watch progress; expand the log panel if you want.
5. Get a `MovieName.<lang>.srt` next to your source. Done.

## Architecture (one-liner per piece)

- **`TrackProber`** — runs `mkvmerge -J` and parses subtitle tracks
- **`MKVToolNixExtractor`** — extracts the selected track to temp `.sup` / `.idx` assets via `mkvextract`
- **`OCRRunner`** — invokes the bundled `macSubtitleOCR` binary, streams progress
- **`SRTFinalizer`** — names and moves the resulting SRT next to the input
- **`SubtitleJob`** — observable state container driving the four-phase UI
- **`ToolchainProbe` / `BundledBinary`** — locate `mkvtoolnix` / `macSubtitleOCR`
  at runtime, preferring the `.app` bundle over any system install

See [docs/superpowers/specs/](docs/superpowers/specs/) for the design rationale
and [docs/superpowers/plans/](docs/superpowers/plans/) for the implementation plan.

## License

MIT, same as upstream macSubtitleOCR. © 2026 Jeff Alldridge / Tent Studios, LLC.

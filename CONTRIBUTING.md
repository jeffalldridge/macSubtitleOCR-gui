# Contributing

Thanks for the interest. This is a small, single-maintainer Mac app, so
contributions are welcome but the bar is "matches the existing code's polish."

## Getting set up

```sh
git clone https://github.com/jeffalldridge/macSubtitleOCR-gui
cd macSubtitleOCR-gui
make build     # universal release build
make test      # Swift Testing suites
make run       # launch from the terminal
```

There are no submodules and no external dependencies. Building needs Xcode 26
or newer; the app itself runs on macOS 15 and later.

## Build, test, and release targets

```sh
make build          # swift build -c release --arch arm64 --arch x86_64
make run            # debug build, launched in place
make test           # Swift Testing suites
make app            # assembles build/macSubtitleOCR-gui.app (ad-hoc signed)
make dmg            # packages the .app into a drag-to-/Applications .dmg
make diff-upstream  # what upstream macSubtitleOCR changed since the port
make clean          # wipes build artifacts
```

For a notarization-ready build (requires an Apple Developer account):

```sh
DEV_ID="Developer ID Application: Your Name (TEAMID12345)" make notarize
make notarize-dmg   # same, plus notarizes and staples the .dmg itself
make release        # clean → notarize → dmg → notarize dmg
```

CI (`.github/workflows/ci.yml`) builds and tests every push. Releases
(`.github/workflows/release.yml`) trigger on a `v*.*.*` tag, then sign,
notarize, package, and publish. The tag must match
`CFBundleShortVersionString` in `Resources/Info.plist`; the workflow checks.
It can also be run by hand:

```sh
gh workflow run Release --ref v1.0.0
```

## Project layout

```
Sources/SubtitleEngine/     pure Swift, no UI — see UPSTREAM.md
  Container/                EBML reader, MKVReader (probe + extract), SubtitleSource, LanguageCode
  PGS/  VobSub/             indexed streams with random-access decoding
  Bitmap/                   IndexedBitmap → CGImage
  Recognition/              Vision wrapper, RecognizedCue
  SRT/                      rendering, parsing, timing rules
  Conversion/               TrackConverter's event stream
Sources/macSubtitleOCR-gui/
  App/                      entry point, delegate, menus, App Intent, self-check
  Model/                    ConversionQueue and friends
  Views/                    sidebar, detail, inspector, settings
Tests/                      Swift Testing, fixtures under SubtitleEngineTests/Fixtures
```

## The engine is a port, not a vendored copy

`Sources/SubtitleEngine/` began as [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR)
source and was restructured for in-process use — indexed streams, per-cue
decoding, progress, cancellation — and several decoding bugs were fixed along
the way. `Sources/SubtitleEngine/UPSTREAM.md` records the upstream commit and
what changed, file by file. Keep it accurate.

To see what upstream has changed since:

```sh
make diff-upstream            # against upstream main
make diff-upstream REF=v1.1.0 # against a tag
```

Merge decoder fixes by hand and update the recorded commit. Ignore changes to
upstream's command-line front end and its optional FFmpeg path — neither is
part of this port.

## Things worth knowing before you touch packaging

**Never use `Bundle.module` in shipping code.** SwiftPM's generated accessor
looks only in `Bundle.main.bundleURL` and a path hardcoded at compile time to
*the build machine's* `.build` directory, then calls `fatalError()`. The
`.app` is hand-assembled and contains no such bundle, so reading it crashes
for every user while working perfectly for whoever built the release
([#3](https://github.com/jeffalldridge/macSubtitleOCR-gui/issues/3)). Test
fixtures are located with `#filePath` for the same reason.

**Gatekeeper assessment comes *after* notarization.** `spctl --assess`
correctly rejects a Developer ID app that has not been notarized yet, so it
must not be a hard gate inside `make-app.sh` — under `set -euo pipefail` its
exit 3 aborts the whole build. It is informational there and asserted in the
Makefile's `notarize` target once the ticket is stapled.

**Both architecture slices must be present.** A single-architecture build runs
fine on the machine that made it and fails for half the users.
`make-app.sh` asserts `arm64` and `x86_64` with `lipo`.

Unit tests run inside the SwiftPM build tree, so they cannot catch any of
this. The app therefore ships a `--self-check` that runs against the assembled
bundle:

```sh
build/macSubtitleOCR-gui.app/Contents/MacOS/macSubtitleOCR-gui --self-check
```

It verifies the Info.plist keys, the compiled icon assets, and a real decode
through the engine. `make app` and CI both run it.

## Before sending a pull request

- `make test` — all green. New logic comes with tests.
- `make build` — clean, no new warnings.
- `make app` — the bundle assembles and self-checks.
- For UI changes, attach a before/after screenshot.
- Keep commits focused. Conventional Commit prefixes (`feat:`, `fix:`,
  `refactor:`, `docs:`, `test:`, `chore:`, `build:`, `ci:`) are appreciated.

## What fits

- Decoding fixes, especially edge-case `.mkv` files where probing or
  extraction misbehaves. A small failing fixture is the best bug report.
- Recognition quality and review-screen ergonomics.
- Tests for anything uncovered in the engine.
- Performance on large files — 50-track UHD remuxes, 5,000-cue tracks.
- Accessibility and localization.
- Documentation.

## What probably doesn't fit, without discussing it first

- Replacing Vision with another recognition engine.
- Cross-platform support. The project is intentionally macOS-only.
- Turning this into a general subtitle editor. Timing, styling, and format
  conversion belong in [Subtitle Edit](https://github.com/SubtitleEdit/subtitleedit).
- Bundling GPL-licensed binaries; the app is deliberately MIT end to end.
- New runtime dependencies. The app currently has none, and that is a feature.
- Large architectural rewrites — open an issue first.

## Code style

- Swift 6, concurrency-aware. The engine is `nonisolated` and `Sendable`; the
  app target defaults to `@MainActor` isolation.
- One clear responsibility per file.
- Pure logic is tested against fixtures; views are not snapshot-tested.
- Error messages are user-facing text — write them for the person who will
  read them in the app, not for a log.

## Screenshots

Docs screenshots are window captures with an alpha channel — the window and
its shadow, nothing of the desktop behind it. That's what ⇧⌘4 then Space
produces interactively; `Scripts/capture-window.sh` does it non-interactively:

```sh
make app && open build/macSubtitleOCR-gui.app
Scripts/capture-window.sh docs/screenshots/main-window.png "" "macSubtitleOCR"
cp docs/screenshots/*.png docs/site/
```

Don't use `screencapture -R x,y,w,h`: a region grab is a flat rectangle, so
whatever is behind the window's rounded corners bleeds into the image and
there's no transparency.

Always **look at the result before committing**. Open and Save panels belong
to the same process, so capturing one by accident publishes your Finder
sidebar. The script skips known panel titles and fails if the output has no
alpha channel, but neither check replaces looking.

## Filing issues

For bugs, include your macOS version, the file you tried, and what the app
showed. A track that decodes wrongly is far easier to fix with a small sample
that reproduces it. For features, describe the use case before the proposed
solution.

## Security

For security-sensitive issues, see [`SECURITY.md`](SECURITY.md) — please don't
open public issues for those.

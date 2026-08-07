# Contributing

Thanks for the interest. This is a small, single-maintainer Mac tool, so
contributions are welcome but the bar is "matches the existing code's polish."

## Getting set up

```sh
git clone --recurse-submodules https://github.com/jeffalldridge/macSubtitleOCR-gui
cd macSubtitleOCR-gui
brew install mkvtoolnix          # runtime dep
make build                       # compiles upstream + this app
make test                        # runs the Swift Testing suites
make run                         # quick dev launch
```

If you forgot `--recurse-submodules`:

```sh
git submodule update --init --recursive
```

## Build, test, and release targets

```sh
make build      # compiles upstream macSubtitleOCR + this app
make run        # builds and runs straight from the terminal
make app        # assembles build/macSubtitleOCR-gui.app (~3.4 MB, ad-hoc signed)
make dmg        # packages the .app into a drag-to-/Applications .dmg
make test       # runs the Swift Testing suites (40+ tests)
make clean      # wipes build artifacts
```

For a notarization-ready build (requires an Apple Developer account):

```sh
DEV_ID="Developer ID Application: Your Name (TEAMID12345)" make notarize
make notarize-dmg   # same, plus notarizes and staples the .dmg itself
make release        # clean → notarize → dmg → notarize dmg (full pipeline)
```

That re-signs with hardened runtime + your Developer ID, submits to Apple's
notary service, and staples the ticket. See [`Makefile`](Makefile) for the
one-time `notarytool store-credentials` setup.

The CI workflow (`.github/workflows/ci.yml`) builds and tests on every push.
Release builds (`.github/workflows/release.yml`) trigger on `v*.*.*` tag
pushes, then sign + notarize + package + publish to GitHub Releases. The same
workflow can be run by hand if a tag push doesn't pick it up:

```sh
gh workflow run Release --ref v0.1.1
```

## Two packaging rules worth knowing

Both of these caused shipped bugs, and neither is visible in a normal local
build. If you touch `Scripts/make-app.sh`, `Package.swift`, or the Makefile's
signing targets, read this first.

**1. Never use `Bundle.module` in shipping code.** SwiftPM's generated
accessor looks only in `Bundle.main.bundleURL` and a path hardcoded at compile
time to *the build machine's* `.build` directory, then calls `fatalError()`.
The `.app` is hand-assembled and contains no such bundle, so reading it
crashes for every user while working perfectly for whoever built the release
([#3](https://github.com/jeffalldridge/macSubtitleOCR-gui/issues/3)). Use
`BundledBinary.moduleResourceBundle()`, which does the same search and returns
`nil` instead of trapping.

**2. Gatekeeper assessment comes *after* notarization.** `spctl --assess`
correctly rejects a Developer ID app that hasn't been notarized yet, so it
must not be a hard gate inside `make-app.sh` — under `set -euo pipefail` its
exit 3 aborts the whole build. It's informational there and asserted in the
Makefile's `notarize` target once the ticket is stapled.

Because unit tests run inside the SwiftPM build tree, they cannot catch either
problem. The app therefore ships a `--self-check` that runs against the
assembled bundle with the SwiftPM resource bundle hidden, i.e. against a
simulated clean machine:

```sh
build/macSubtitleOCR-gui.app/Contents/MacOS/macSubtitleOCR-gui --self-check
```

`make app` and CI run it automatically; it exits non-zero if the `.app` is not
self-contained. Verify packaging changes against a built `.app` — ideally a
downloaded release artifact — not just `swift test`.

## Updating the upstream OCR engine

The repository pins `Vendor/macSubtitleOCR` to a specific upstream tag for
reproducible builds. To bump it:

```sh
make update                 # pulls latest from upstream/main, rebuilds
git add Vendor/macSubtitleOCR
git commit -m "Bump macSubtitleOCR to <upstream-sha>"
```

After a new upstream release tag, you can also do
`git -C Vendor/macSubtitleOCR checkout v1.2.3` to lock to that version
specifically.

## Before sending a PR

- Run `make test` — all tests green.
- Run `make build` — clean, no new warnings.
- Run `swift build -c release` (which `make build` invokes) without errors.
- For UI changes, attach a before/after screenshot.
- Keep commits focused. Conventional Commit prefixes (`feat:`, `fix:`,
  `refactor:`, `docs:`, `test:`, `chore:`) help auto-changelog tools.

## What kinds of contributions fit

- Bug fixes, especially on edge-case `.mkv` files where track probing or
  extraction misbehaves.
- UX polish — clearer copy, better error states, additional keyboard
  shortcuts.
- Tests for any uncovered logic in `TrackProber`, `MKVToolNixExtractor`,
  `OCRRunner`, `SRTFinalizer`.
- Performance improvements on large files (50+ track UHD remuxes).
- Documentation improvements.

## What probably doesn't fit (without discussion first)

- Replacing the upstream OCR engine with something else.
- Cross-platform support (the project is intentionally macOS-only).
- Bundling additional GPL-licensed binaries; we deliberately keep the
  shipping app MIT.
- Major architectural rewrites — file an issue first to talk through it.

## Code style

Follow the existing patterns:

- Swift 6, concurrency-aware (`async`/`await`, actors, `Sendable`).
- Each file should have one clear responsibility.
- Pure components (parsing, argument construction) are TDD'd against
  fixtures; views are not snapshot-tested.
- Error messages should be human-readable — they surface in the UI.
- Don't introduce new runtime dependencies without raising it in an issue.

## Filing issues

For bugs include the macOS version, the file you tried (or a `mkvmerge -J`
dump if you can't share it), and the relevant log lines from the in-app log
panel. For features, describe the use case before the proposed solution.

## Security

For security-sensitive issues, see [`SECURITY.md`](SECURITY.md) — please
don't open public issues for those.

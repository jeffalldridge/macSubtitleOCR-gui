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

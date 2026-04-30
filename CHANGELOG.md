# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-04-30

Initial public release.

### Added

- SwiftUI macOS app that wraps the [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR)
  command-line tool.
- Drag-and-drop input for `.mkv`, `.mks`, `.sup`, `.sub`, and `.idx` files.
- Multi-track selection with checkboxes — pick one or many PGS / VobSub tracks
  in a single run; each produces its own SRT.
- Auto-tick of every track whose language matches your language preference
  (e.g. typing `en,jpn` auto-ticks all English and Japanese PGS tracks).
- Track filter / search field (shown when a file has more than 6 tracks),
  matching against language code and track name.
- Locale-aware track display: ISO 639 codes ("eng") render as localized
  names ("English") in the picker.
- Default / forced track badges from `mkvmerge` metadata.
- Persistent OCR options — last-used language, invert flag, and custom-words
  carry across sessions and across new files (UserDefaults-backed).
- Live progress UI per stage (extracting → OCR → finalizing) with a percent
  indicator and per-stage explanation copy.
- Cancel button that genuinely terminates the running process via Swift task
  cancellation; partial work is cleaned up.
- Output filename rule that distinguishes SDH from regular and Commentary
  tracks: `Movie.eng.english-sdh.srt`, `Movie.jpn.japanese-commentary.srt`.
- SRT preview cards on the Done screen — first 3 cues of each output with
  timestamps and total cue count, plus reveal-in-Finder per file.
- Self-contained `.app` bundle with `macSubtitleOCR` embedded. Requires
  MKVToolNix on the host (`brew install mkvtoolnix`).
- Custom app icon rendered from an Icon Composer source.

### Notes

- Apple Silicon only for v0.1.
- Targets macOS 14 (Sonoma) or newer.
- The shipped `.dmg` is signed with a Developer ID certificate and notarized.

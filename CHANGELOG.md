# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **A destination menu in the toolbar**, next to the button that starts the
  work, so where the subtitle files land is visible at the moment it matters.
  Next to the film is the default. You can pick a folder, or ask to be asked
  each time, and the run puts up a folder chooser before it starts.
- **A play button.** The primary action is a filled play button in the top
  right, and it becomes Stop in the same place while a run is going.

### Fixed

- **Crash while scrolling the queue.** Table cells and menus are rendered in
  their own hosting contexts, and a view that looked up shared state from
  inside one of those trapped when the state had not travelled with it. Every
  cell, menu, and toolbar item is handed what it needs now.
- **Track checkboxes could not be clicked.** The column was narrower than a
  checkbox plus the padding a table puts around it, so the control was drawn
  but clipped to almost nothing.
- **Opening a file re-read its index once per track.** On a remux with
  twenty-eight subtitle tracks that was fifty-six index walks and fifty-six
  memory maps for one batch; it is one of each now.
- **Files on a network share are no longer memory-mapped.** Every page fault
  was a round trip, and a share that dropped mid-read killed the app outright.
  Local disks, including external ones, still map.
- **Revert All Edits can be undone**, like every other edit in the app.
- **Reset All Settings asks first.**
- The progress bar can no longer tick backwards.
- Counts read correctly at one: "1 track, included" rather than "1, included",
  and a lone text subtitle track is described in the singular.
- The Recognize button says what is missing when it is disabled.
- The accept checkbox in the clean-up sheet has an accessibility label.

### Changed

- **The window is one column, not two.** The file list was a sidebar taking a
  quarter of the width from the cue review, which is the part of the app that
  needs it: a subtitle image and its text side by side. The queue is now a
  table across the top of the window, with the review below it and a divider
  the user can drag. Every file and track is visible at once with its language,
  cue count, and what it is doing.
- **The status bar is always there.** It used to appear when a run started,
  which resized the window at the least helpful moment. It now shows what is
  queued when idle, progress while running, and the result when finished.
- **Track status says what it means.** Each row shows an icon and a word rather
  than an icon alone, and colour is rationed: green only for a subtitle file
  that is written and needs nothing, orange for something to look at, red for
  something that did not happen.
- **Search and the review filter moved into the track header**, next to the
  cue list they filter, rather than the window toolbar which now belongs to the
  queue. Find (⌘F) puts the cursor in the search field.
- **Remove (⌘⌫)** takes the selected file out of the queue, from the toolbar or
  the File menu.

### Fixed

- **Opening a large file took a minute.** Foundation's "map the file if it is
  safe" decides safety by volume and declines on most external drives — where
  declining means copying the file into memory instead. On a 30 GB remux on an
  external drive that was 58.7 seconds and 1.4 GB of RAM before a single byte
  was parsed. Mapping unconditionally reads the same file's track list in
  0.027 seconds.
- **Reading a subtitle track read the whole film.** Matroska files carry an
  index saying which parts of the file hold each track. The app now follows
  it, and reads a few hundred megabytes instead of thirty gigabytes. A track
  that took about fifty-five seconds now takes 0.07 seconds. Files without an
  index, and indexes that turn out to be wrong, still fall back to reading
  everything.
- **Some tracks came out empty.** Remuxers routinely compress subtitle frames,
  which the reader did not undo, so the decoder was handed deflated bytes and
  found nothing. Both compression schemes Matroska defines for subtitles are
  now handled, and an encrypted track says so instead of appearing blank.
- **The window froze while a file was being read.** The container walk ran on
  the main actor, so it blocked the interface — including the progress bar
  that was meant to show it working.

## [1.0.0] — 2026-09-10

The app stops being a front-end for command-line tools and becomes a complete
macOS application. It reads Matroska containers, decodes PGS and VobSub, and
runs Apple Vision itself — then lets you check and correct every cue before
you mux.

### Removed

- **The MKVToolNix requirement.** The app no longer shells out to `mkvmerge`
  or `mkvextract`, so there is nothing to install with Homebrew. The
  "MKVToolNix is required" card is gone.
- **The bundled `macSubtitleOCR` command-line binary** and the git submodule
  that produced it. The engine is now Swift source compiled into the app.

### Added

- **Cue review.** Every recognized cue is listed with the exact bitmap the
  recognizer read, its timing, and its text. Cues Vision was unsure about are
  flagged. Edit any cue inline and the `.srt` is rewritten as you type, with
  full undo.
- **Cue preview before recognition.** As soon as a track is indexed, its cues
  and their images are browsable — so you can confirm a track is the one you
  want before spending time on it.
- **Batch conversion.** Add any number of files, or drop a folder to queue a
  whole season. Files and their tracks appear as an outline in the sidebar.
- **A real macOS window.** `NavigationSplitView` with a sidebar, a detail
  view, an inspector for recognition and output options (⌥⌘I), and a status
  bar with overall progress and a Cancel button.
- **Settings** (⌘,) for output location, conflict policy, default languages,
  invert, custom words, notifications, and updates.
- **Finder integration.** Open With for MKV, MKS, SUP, SUB, and IDX; a
  Services menu item ("Recognize Subtitles"); Open Recent; Dock drops.
- **A Shortcuts action**, "Recognize Subtitles", that converts files without
  opening a window.
- **Notifications** when a run finishes in the background, and a progress bar
  on the Dock icon while it runs.
- **Clean Up with Apple Intelligence** (macOS 26): the on-device model
  proposes fixes for character-level mistakes in flagged cues, shown as
  before/after suggestions you accept or reject one at a time.
- **Translate…**: exports a translated copy of a recognized track using the
  on-device Translation framework.
- **An Acknowledgements window** and an About panel crediting the upstream
  project, with full license texts.
- **A universal binary.** The published `.dmg` runs natively on Apple silicon
  and Intel.
- **Track languages drive recognition.** A track tagged `jpn` is recognized as
  Japanese even when your default is English.
- **An output folder option.** Write every `.srt` to one folder instead of
  next to each source.
- **An update check** against the project's GitHub releases, once a day, with
  an opt-out in Settings. It never downloads or installs anything.

### Changed

- **Minimum macOS is now 15 (Sequoia)**, for Vision's current recognition API
  and its per-line confidence scores.
- **Track probing is instant.** Reading the track list only parses the
  Matroska `Info` and `Tracks` elements, so a 40 GB remux lists its tracks as
  fast as a small file.
- **Extracted tracks are cached** under `~/Library/Caches`, so reopening a
  file skips the extraction pass entirely.
- **Progress is per cue**, not per stage: "312 of 1,204 cues" rather than a
  three-step guess.
- The app is named **macSubtitleOCR** throughout; `macSubtitleOCR-gui`
  remains the repository, bundle, and executable name.
- Your language, invert, and custom-word settings from 0.x are carried over
  the first time 1.0 runs.

### Fixed

**The app could launch with no window at all.** On a Mac that had run
earlier versions, the main window was sometimes never created: the app
appeared in the Dock with its menu bar, and nothing else. The cause was
AppKit's saved window state — the app now opts out of it, since a
single-window utility has nothing worth restoring, and a bad record should
never be able to hide the interface.

**Notifications no longer break a source build.** Reading the notification
centre during launch raises an exception outside a real `.app`, which killed
`make run`.

**Cancel now works while a track is being read.** Cancelling during the
extraction phase did nothing at all: the work ran on a task that could not
see the cancellation, so a large MKV kept going to the end regardless.

**Reverting an edit now reaches the file.** "Revert to Recognized Text" and
"Revert All Edits" both restored the text on screen and left the `.srt`
holding the edits, with nothing on screen saying the two had diverged.

**A cue you were still typing is no longer lost on quit**, and two tracks in
one run can no longer write to the same filename and destroy each other.
Files dropped on the window mid-run join the run instead of being silently
ignored, redo no longer breaks the undo chain, and the same track can no
longer be read out of a container twice at once.

**Malicious subtitle files can no longer crash the app.** An adversarial
review of the new parsers found six ways a crafted file could take it down: a
120 KB Matroska file that overflowed the stack through nested elements, three
integer traps on out-of-range timestamps and track numbers, an infinite cue
time smuggled in through a VobSub index, and a 92-byte PGS file that asked
for a four-gigabyte allocation. All are fixed and covered by tests, alongside
fuzzing that truncates and corrupts real files at thousands of offsets.

Five decoding bugs, found while porting the engine and fixed here. Each
produced wrong output rather than an error, so they were invisible before:

- **Subtitles cut short by fades.** A cue ended at the next segment of any
  kind, so a palette-only update — how fade-outs are encoded — truncated it.
  A cue now ends only when the screen is cleared or a new image is drawn.
- **Multi-part captions losing everything but the last piece.** Display sets
  that define several objects (a line of dialogue plus a positioned label, for
  instance) kept only the final object. All objects are now composited at
  their real positions.
- **VobSub subpictures under about 2 KB decoding incorrectly**, because the
  MPEG packet length was written as a fixed size rather than the actual
  payload length.
- **VobSub cue timing drift**, from adding raw 1/1024-second control delays to
  a value measured in seconds.
- **Every cue capped at five seconds**, even when the stream carried a longer
  end time. The decoded end is now kept, clamped only so cues cannot overlap;
  the five-second rule applies only when the end is genuinely unknown.
- **A cue that could not be decoded threw away the whole track.** One
  unreadable cue now renders blank and the rest of the track is kept.
- **Subtitles that re-display an earlier image were skipped**, and a track
  whose `Info` element followed its `Tracks` element got the wrong timestamp
  scale, and so the wrong timings throughout.

### Notes

- Upgrading is safe: output naming is unchanged, no files need migrating, and
  your recognition settings carry over.
- Version 0.2 users on macOS 14 should stay on
  [v0.2.0](https://github.com/jeffalldridge/macSubtitleOCR-gui/releases/tag/v0.2.0).

## [0.2.0] — 2026-08-07

A user-interface release: the app now follows the macOS Human Interface
Guidelines more closely, and scales to files with many subtitle tracks.

### Changed

- **Native macOS window structure.** The document identity now lives in the
  title bar (`sintel.mks — 2 subtitle tracks`) instead of a custom header
  duplicating the app name inside the content area, and the window has a
  toolbar with an Open button.
- **Real File and Help menus.** File ▸ Open… (⌘O) and Close File (⇧⌘W) work
  from the menu bar; Help links to the site and the issue tracker. Opening a
  file is no longer reachable only from the drop screen.
- **Track picker is a native `List`** with row separators and selection
  affordances, replacing a hand-rolled stack of toggles inside a fixed-height
  scroll view. It now grows with the window instead of being capped at 280 pt.
- Windows resize freely above a sensible minimum (`contentMinSize`); the
  previous `contentSize` policy pinned the window to its content.
- OCR options use a grouped `Form`, matching system settings layout.
- Typography follows Apple conventions: real ellipses, em dashes in track
  titles, and `·` separators for track metadata.

### Fixed

- Log and preview panels used `Color.black.opacity(0.06)`, which was close to
  invisible in Dark Mode. They now use semantic fills that adapt to both
  appearances.
- The Cancel button during a run was styled `.destructive` (red); cancelling
  isn't a destructive action, and it now responds to Escape.
- Track rows were visually misaligned: the leading captions glyph centred on
  the two-line label while the checkbox aligned to the title. The glyph is
  gone — "Default" and "Forced" badges already carried that information.

### Added

- Log panels auto-scroll to follow new output and have a copy-to-clipboard
  button.
- VoiceOver labels for icon-only controls, drop target, progress, and track
  rows.

## [0.1.1] — 2026-08-06

### Fixed

- **Crash on "Run OCR" ([#3](https://github.com/jeffalldridge/macSubtitleOCR-gui/issues/3)).**
  The app terminated immediately (`EXC_BREAKPOINT` / SIGTRAP) for every user the
  moment OCR started. Locating the embedded `macSubtitleOCR` binary read
  SwiftPM's generated `Bundle.module` accessor, which searches only
  `Bundle.main.bundleURL` and a path hardcoded to the *build machine's* `.build`
  directory, then calls `fatalError()` when neither exists. The shipped `.app`
  contains no such bundle, so the accessor trapped on every machine except the
  one that produced the release — which is why it was not caught before
  shipping. Binary lookup no longer depends on that accessor.

- **Release builds failing at `make app`.** The Gatekeeper check in
  `Scripts/make-app.sh` ran before notarization, where `spctl` correctly
  rejects a signed-but-not-yet-notarized app; under `set -euo pipefail` its
  exit 3 aborted the build. The assessment is now informational there and
  asserted in `make notarize` after the ticket is stapled.

### Added

- `--self-check` flag that verifies an assembled `.app` resolves everything it
  needs from inside the bundle. `Scripts/make-app.sh` and CI now run it against
  a simulated clean machine, so a packaging regression of this kind fails the
  build instead of reaching users.

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

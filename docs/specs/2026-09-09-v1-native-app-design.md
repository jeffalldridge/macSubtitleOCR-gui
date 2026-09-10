# macSubtitleOCR 1.0 — Native App Design

**Date:** 2026-09-09
**Status:** Approved for implementation
**Author:** Jeff Alldridge + Claude
**Supersedes:** the v0.x architecture described in
[`2026-04-30-macSubtitleOCR-gui-design.md`](2026-04-30-macSubtitleOCR-gui-design.md)

## Purpose

Turn macSubtitleOCR-gui from a front-end that shells out to two command-line
tools into a complete, self-contained macOS app. One job, done end to end:
open Blu-ray or DVD bitmap subtitles, see them, recognize them with Apple
Vision, review and fix the text, and get clean `.srt` files.

## Goals

1. **Self-contained.** No Homebrew, no MKVToolNix, no bundled CLI. The app
   reads MKV containers, decodes PGS and VobSub, and runs Vision itself.
   The bundle stays MIT-licensed and becomes a universal binary.
2. **Feels like a Mac app.** Sidebar/detail window, inspector, Settings,
   Open Recent, Finder "Open With" and Dock drops, notifications, an
   Acknowledgements window, and standard menus. Follows the Human Interface
   Guidelines; uses standard SwiftUI controls so it picks up the current
   system look automatically.
3. **Honest progress.** Per-cue progress, real cancellation, and a visible
   count of cues that need a second look.
4. **Batch.** Drop several files (a whole TV season) and run them in one go.
5. **Review before you mux.** Every cue shows the exact bitmap next to the
   recognized text. Low-confidence cues are flagged. Edits rewrite the SRT.

## Non-goals

- Editing timing, styling, or format conversion (use Subtitle Edit).
- MP4 input, `.m2ts` input, text-subtitle export.
- App Store distribution or sandboxing (see Decisions).
- Automatic updates via Sparkle (see Decisions).

## Decisions

| Decision | Choice | Why |
|---|---|---|
| OCR engine | Vendor the MIT-licensed engine from [ecdye/macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR) as a Swift library target, adapted for progress, cancellation, random access, and multi-object PGS. | Removes the bundled CLI and the `Bundle.module` class of packaging bug. Enables per-cue progress and bitmap preview. Attribution preserved in the source headers, `THIRD_PARTY_LICENSES.md`, About, and the Acknowledgements window. |
| MKV reading | Own memory-mapped EBML/Matroska reader. Probing reads only the `Tracks` element; extraction scans clusters for the chosen track. | Removes the GPL MKVToolNix runtime dependency and the Homebrew requirement. Probing becomes instant. |
| Minimum macOS | 15 (Sequoia) | Vision's modern `RecognizeTextRequest` API is macOS 15+. One code path, per-line confidence, native async. |
| Architecture | Universal (arm64 + x86_64) | Nothing external to bundle any more, so `swift build --arch arm64 --arch x86_64` is enough. |
| Sandbox | Off (hardened runtime on) | Writing `Film.eng.srt` next to `Film.mkv` needs sibling access the sandbox does not grant without a folder prompt. Not App Store bound. |
| Updates | Lightweight check against the GitHub Releases API, opt-out in Settings, plus "Check for Updates…" in the app menu | Sparkle needs a signing key and appcast infrastructure; a release check needs neither and never downloads anything by itself. |
| Version | 1.0.0 | Feature-complete for its purpose; also a compatibility break (macOS 15). |
| Upstream submodule | Removed. `Sources/SubtitleEngine/UPSTREAM.md` records the upstream commit and every adaptation; `Scripts/diff-upstream.sh` diffs against a fresh upstream clone. | The engine is now modified source, so bumps are manual merges anyway; a submodule only adds clone friction. |
| Build system | SwiftPM plus `Scripts/make-app.sh` | Already proven with notarization. Icon Composer `.icon` files compile with `actool`, so no Xcode project is needed. |

## Architecture

Three SwiftPM targets.

```
SubtitleEngine (library, no UI)
├── Container/   MKVReader (EBML), SubtitleSource, TrackInfo
├── PGS/         PGSStream (index + per-cue decode), PCS/PDS/ODS parsers, RLE
├── VobSub/      VobSubStream (index + per-cue decode), IDX parser, RLE
├── Bitmap/      IndexedBitmap → CGImage (display / recognition variants)
├── Recognition/ TextRecognizer (Vision), RecognitionOptions, RecognizedCue
├── SRT/         SRTCue, SRTFile (render + parse), timing rules
└── Conversion/  TrackConverter: extract → index → recognize, streaming events

macSubtitleOCR-gui (executable, SwiftUI)
├── App/         App, AppDelegate (open files, notifications, dock), Commands
├── Model/       ConversionQueue, QueueFile, QueueTrack, AppSettings,
│                OutputNaming, StreamCache, RecentFiles, UpdateChecker
└── Views/       MainWindow, Sidebar, EmptyState, FileDetail, TrackDetail,
                 CueList, CuePreview, Inspector, StatusBar, Settings,
                 Acknowledgements

Tests
├── SubtitleEngineTests   fixtures: sintel.{mks,sup,sub,idx,srt} (MIT, upstream)
└── macSubtitleOCR-guiTests
```

### Engine data flow

```
URL ──SubtitleSource.open──▶ .mkv / .pgs / .vobsub
        │
        ├─ probe() ─────────▶ ContainerInfo { tracks: [TrackInfo], textTrackCount, duration }
        │
        └─ stream(track, progress) ──▶ SubtitleStream (memory-mapped .sup / .sub+idx)
                                           │
                                           ├─ index() ──▶ [CueInfo] (start, end, byte range)
                                           └─ bitmap(at:) ──▶ IndexedBitmap (on demand, cached)
                                                                 │
TextRecognizer.recognize(bitmap, options) ◀──────────────────────┘
        │
        └─▶ RecognizedCue { text, lines[confidence, box], confidence }
                │
SRTFile.render([SRTCue]) ──▶ Film.eng.english-sdh.srt
```

`TrackConverter.run(stream, options)` yields an `AsyncThrowingStream<Event>`:
`.indexed(count)`, `.progress(done, total)`, `.cue(RecognizedCue)`,
`.finished([RecognizedCue])`. It honors `Task` cancellation between cues.
Recognition runs up to four cues concurrently (bounded task group).

### Engine details

- **MKVReader** works on a memory-mapped `Data`. It reads `Info`
  (TimestampScale, Duration, Title) and `Tracks` (number, type, CodecID,
  Language, LanguageBCP47, Name, FlagDefault, FlagForced, CodecPrivate).
  Extraction walks top-level Segment children, skips non-cluster elements
  by size, handles unknown-size clusters, and reads SimpleBlock and
  BlockGroup/Block with all three lacing modes. PGS blocks are re-wrapped
  as `.sup` display sets (`PG` + PTS + DTS header per segment); VobSub
  blocks are re-wrapped as MPEG-PS packets plus a synthesized `.idx`,
  exactly as upstream does, so the standalone parsers handle both.
- **PGSStream** indexes display sets without decoding RLE. A cue is a
  display set that defines objects. Its end is the PTS of the next display
  set that clears the screen or defines new objects; palette-only updates
  (fades) do not end a cue. Multiple composition objects in one display set
  are composited onto a canvas using PCS positions, and the PDS referenced
  by the PCS palette ID is used.
- **VobSubStream** indexes from the `.idx` timestamps and decodes one
  subpicture on demand.
- **IndexedBitmap** holds 8-bit palette indices plus an RGBA palette. It
  renders a display image (original colors, transparent background, cropped
  to content) and a recognition image (black glyphs on white, or inverted).
- **TextRecognizer** wraps `RecognizeTextRequest` (accurate level, language
  correction on, custom words, languages). A cue's confidence is the lowest
  line confidence; cues below 0.6, or empty on a non-empty bitmap, are
  flagged for review. The English `l → I` correction from upstream is kept
  and is switchable.
- **SRTFile** renders `HH:MM:SS,mmm` cues. End-time rule: use the decoded
  end when present, clamped so it does not overlap the next cue; when
  absent, `min(next start − 0.1 s, start + 5 s)`.
- **Language mapping.** Track languages arrive as ISO 639-2 (`eng`) or
  BCP 47. `Locale.LanguageCode` maps terminology codes; a small table maps
  the legacy bibliographic codes (`ger`, `fre`, `chi`, `dut`, `cze`, `gre`,
  `rum`, `per`, `ice`, `mac`, `may`, `alb`, `arm`, `baq`, `bur`, `geo`,
  `slo`, `tib`, `wel`). A track's language is used for recognition when
  Vision supports it, ahead of the user's default list.

## App model

- **`AppSettings`** (UserDefaults-backed, observable): output location
  (next to source / chosen folder), conflict policy (add suffix / replace),
  default recognition languages, invert, custom words, `l → I` correction,
  notify when done, open review when done, check for updates.
- **`ConversionQueue`** (`@MainActor @Observable`): ordered `[QueueFile]`.
  - `QueueFile`: `url`, `state` (probing / ready(ContainerInfo) / failed),
    `tracks: [QueueTrack]`.
  - `QueueTrack`: `info: TrackInfo`, `isIncluded`, `status`
    (idle / queued / extracting(fraction) / indexing /
    recognizing(done, total) / saving / done / failed(message) / cancelled),
    `stream` (loaded lazily for preview, reused for the run), `cues:
    [ReviewCue]`, `outputURL`, `issues: [String]`.
  - Run options for the current queue (seeded from settings, edited in the
    inspector): languages, invert, custom words, `l → I`, output location.
  - `run()` converts included tracks sequentially, file by file; `cancel()`
    cancels the task. Overall progress is completed tracks plus the current
    track's fraction.
- **`ReviewCue`**: `index`, `start`, `end`, `text`, `originalText`,
  `confidence`, `needsReview`. Editing a cue registers an undo action and
  schedules a debounced rewrite of the SRT.
- **`StreamCache`**: extracted MKV tracks are written to
  `~/Library/Caches/<bundle-id>/streams/<hash>.sup` keyed by path, size,
  modification date, and track number, so reopening a file is instant.
  Pruned on launch to 2 GB / 14 days.
- **`OutputNaming`**: `<base>.<lang>[.<sanitized-name>].srt` in the output
  folder; unchanged from v0.2 apart from the conflict policy.
- **`RecentFiles`**: `NSDocumentController.shared.noteNewRecentDocumentURL`
  feeds a File ▸ Open Recent submenu and the Dock menu.
- **`UpdateChecker`**: at most once per day, GET
  `api.github.com/repos/jeffalldridge/macSubtitleOCR-gui/releases/latest`,
  compare `tag_name` with the bundle version, surface a non-modal notice
  with a Download link. Never downloads or installs.

## Window and views

One main window (`WindowGroup`, default 1000 × 660, min 760 × 480), a
`Settings` scene, and an `Acknowledgements` window.

- **Empty state** (queue empty): a drop zone filling the window — icon,
  "Drop video or subtitle files", supported formats, and a "Choose Files…"
  button. The whole window accepts drops in every state.
- **Main layout** (`NavigationSplitView`):
  - **Sidebar**: outline of files, each expanded to its bitmap subtitle
    tracks. A track row has an include checkbox, the language name and track
    name, a codec badge, Default/Forced badges, and a trailing status:
    nothing, a spinner, `312 / 1,204`, a green check with "3 to review", or
    a warning glyph. A file row shows the filename and a summary
    ("2 PGS tracks · 1 text track"); its context menu offers Remove, Reveal
    in Finder, Include All, Include None. Selection drives the detail view.
  - **Detail, file selected**: file summary (path, size, duration, tracks),
    plus a "Recognize N Selected Tracks" button.
  - **Detail, track selected** (`TrackDetailView`): header (title, language,
    flags, status), then a cue list. Before recognition it shows cue
    thumbnails and times as soon as the stream is indexed ("1,204 cues").
    After recognition each row shows the thumbnail, the time range, the text
    (editable), and a review flag when confidence is low. The selected cue
    renders at full size in a preview pane above the list on a dark card.
    Toolbar: search field, "Needs review" filter toggle, Reveal in Finder.
    Arrow keys move the selection; Return starts editing; ⌘Z undoes an edit.
  - **Inspector** (⌥⌘I, `.inspector`): Recognition — languages (checklist of
    the 30 Vision languages, with the track's own language always added),
    Invert, Custom words, `l → I` correction; Output — location and a live
    filename preview for the selected track; "Reset to Defaults".
  - **Status bar** (bottom inset, visible during and after a run):
    "Recognizing English (SDH) · 312 of 1,204 cues", a linear progress bar,
    Cancel (⌘.); afterwards "Saved 3 subtitle files · 5 cues to review",
    Reveal All, Clear.
- **Toolbar**: Add Files (⌘O), Recognize (⌘R, primary; becomes Cancel while
  running), Inspector toggle.
- **Menus**: File (Open…, Open Recent, Add Files…, Clear Queue, Reveal in
  Finder, Close), Edit (standard plus Include All / Include None),
  Track (Recognize, Cancel, Reload Preview), View (Show/Hide Inspector,
  Needs Review Only), Window, Help (Help, Report an Issue…,
  Acknowledgements). App menu: About (standard panel with credits),
  Check for Updates…, Settings….
- **Settings** (⌘,): General (output location, on conflict, notify when
  done, open review when done, check for updates) and Recognition (default
  languages, invert, custom words, `l → I`).
- **Acknowledgements**: the macSubtitleOCR MIT license in full, the app's
  own license, and a note on SF Symbols.
- **Notifications**: when a run finishes and the app is not frontmost, post
  a user notification ("Recognition complete — 3 subtitle files saved");
  activating it brings the window forward. Authorization is requested the
  first time a run completes with the setting on.
- **Dock**: a progress bar on the Dock tile during a run.
- **Finder**: `CFBundleDocumentTypes` for `mkv`, `mks`, `sup`, `sub`, `idx`
  (Alternate rank) so the app appears in Open With and accepts Dock drops.
  Dropping `.sub` or `.idx` locates its sibling automatically.

## Apple platform integrations

Everything below uses a system framework; nothing is downloaded or sent off
the Mac. Features that need a newer OS are gated with `#available` and are
hidden, not disabled, on older systems.

| Integration | Framework | Minimum | What it does |
|---|---|---|---|
| Text recognition | Vision `RecognizeTextRequest` | 15 | In-process OCR with per-line confidence; automatic language detection when a track has no language tag. |
| Clean Up with Apple Intelligence | FoundationModels | 26 (Apple Intelligence on) | For cues flagged for review, asks the on-device model to fix OCR character mistakes only, keeping meaning and line breaks. Results appear as suggestions with a before/after diff; the user accepts each one or all. Shown only when `SystemLanguageModel.default.availability == .available`. |
| Translate… | Translation `TranslationSession` | 15 | Exports a translated copy of a recognized track as `<base>.<lang>.srt`, using on-device language packs (the system prompts to download a pack if needed). |
| Writing Tools | AppKit / SwiftUI | 15.1 | Available automatically in the cue text editor. |
| Shortcuts and Spotlight | App Intents | 15 | "Recognize Subtitles" intent: takes files, optional language, returns SRT files. Registered as an App Shortcut. |
| Finder Services | NSServices | 15 | "Recognize Subtitles with macSubtitleOCR" in the Finder context menu adds the selected files to the queue. |
| Open With / Dock drops | Launch Services document types | 15 | The app appears in Open With for MKV, MKS, SUP, SUB, IDX. |
| Open Recent | `NSDocumentController` | 15 | File ▸ Open Recent and the Dock menu. |
| Notifications | UserNotifications | 15 | Completion notice when the app is in the background. |
| Dock progress | `NSDockTile` | 15 | Progress bar on the Dock icon during a run. |
| Onboarding tips | TipKit | 15 | Two tips: drop-to-add and inline cue editing. Shown once. |
| Haptics | SwiftUI `sensoryFeedback` | 15 | Success feedback on trackpads when a run completes. |
| Diagnostics | `os.Logger`, `OSSignposter` | 15 | Engine logs and intervals visible in Console and Instruments. |
| Icon | Icon Composer `.icon` via `actool` | build-time (Xcode 26) | Layered icon that renders as Liquid Glass on macOS 26 and as a flat icon on 15. |
| Liquid Glass | SwiftUI (macOS 26 SDK) | 26 | Standard toolbar, sidebar, and inspector adopt the system look; `ToolbarSpacer` groups toolbar items where available. |
| Language mapping | Foundation `Locale.Language` | 15 | ISO 639 handling and localized language names. |
| Concurrency | Swift 6.2 default MainActor isolation (app target) | build-time | Fewer annotations in UI code; the engine stays nonisolated. |

## Error handling

- Probe failures (not a Matroska file, no bitmap tracks) mark the file
  failed with a plain-language message and keep it in the queue so the user
  can see what happened and remove it.
- A failed track does not stop the run; the run continues and the status bar
  totals failures. Each track keeps an `issues` list (engine warnings such as
  "3 cues had invalid RLE data and were left blank") shown in the detail.
- Cancellation leaves completed SRTs in place, discards the in-flight track,
  and marks remaining tracks cancelled.
- Output write failures (permissions, read-only volume) fail the track with
  the system error text and suggest choosing an output folder in Settings.

## Packaging and release

- `make build` → universal release build; `make app` assembles the bundle,
  compiles `Resources/AppIcon.icon` with `actool` (Assets.car + icns),
  generates nothing else at build time, signs (ad hoc or Developer ID with
  hardened runtime), verifies, and runs `--self-check` (bundle sanity:
  Info.plist keys, icon assets, universal slices).
- `make notarize`, `make dmg`, `make release` unchanged in spirit.
- CI and Release workflows move to `macos-26` with Xcode 26; no Homebrew
  step. Release is still triggered by a `v*.*.*` tag.
- `Info.plist`: `LSMinimumSystemVersion 15.0`, document types, `CFBundleIconName AppIcon`,
  `NSUserNotificationsUsageDescription`, version 1.0.0.

## Testing

- Engine (Swift Testing, fixtures from upstream): MKV probe of `sintel.mks`
  (two tracks, languages, flags); extraction of each track matches decoding
  the standalone `sintel.sup` / `sintel.sub`; PGS index count and timings;
  per-cue decode is random-access; VobSub decode; multi-object PGS
  compositing (synthetic fixture); SRT render/parse round trip and end-time
  rules; language mapping; recognition of `sintel.sup` reaches ≥ 95 %
  similarity to `sintel.srt` (serialized suite, real Vision).
- App: queue state transitions, include/select logic, output naming and
  conflict policy, settings persistence, review-flag rule, update version
  comparison, stream cache keys.
- Views are exercised manually; screenshots refreshed for the README and
  site.

## Documentation and release artifacts

README, CHANGELOG (1.0.0), CONTRIBUTING, THIRD_PARTY_LICENSES, SECURITY,
the site under `docs/site/`, and the local `AGENTS.md` are updated to the
new architecture. The roadmap document for the preview scrubber is marked
delivered in its simpler form.

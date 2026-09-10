# macSubtitleOCR

> **Drop a Blu-ray rip, get clean `.srt` files.**
> A native macOS app that turns PGS and VobSub bitmap subtitles into SubRip
> text with Apple's Vision framework — then lets you check and fix every cue
> before you mux.

[![CI](https://github.com/jeffalldridge/macSubtitleOCR-gui/actions/workflows/ci.yml/badge.svg)](https://github.com/jeffalldridge/macSubtitleOCR-gui/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/jeffalldridge/macSubtitleOCR-gui)](https://github.com/jeffalldridge/macSubtitleOCR-gui/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/jeffalldridge/macSubtitleOCR-gui/total)](https://github.com/jeffalldridge/macSubtitleOCR-gui/releases)
[![Website](https://img.shields.io/badge/website-macsubtitleocr-0a7ea4)](https://jeffalldridge.github.io/macSubtitleOCR-gui/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Universal](https://img.shields.io/badge/arch-universal-orange)

**[⬇ Download the latest .dmg](https://github.com/jeffalldridge/macSubtitleOCR-gui/releases/latest)** — signed, notarized, universal, no dependencies.
**🌐 [Website & FAQ](https://jeffalldridge.github.io/macSubtitleOCR-gui/)**

Drop `.mkv`, `.mks`, `.sup`, `.sub`, or `.idx` files, tick the subtitle
tracks you want, and get `.srt` files next to your source — ready to mux
into MP4 soft-subs with [Subler](https://subler.org) or your tool of choice.

By Jeff Alldridge / [Tent Studios, LLC](https://tentstudios.com). The
recognition engine is derived from
[macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR) by Ethan Dye,
MIT-licensed. See [Credits](#credits).

---

## What it does

- **Reads the container itself.** Matroska parsing, PGS and VobSub decoding,
  and Vision recognition all happen inside the app. No Homebrew, no
  MKVToolNix, no command-line tools, no helper binaries.
- **Shows you every track.** Language, track name, default and forced flags,
  and the cue count, so "English (SDH)" and "Japanese (Commentary)" are
  obvious at a glance. Tick as many as you like.
- **Batch.** Drop a folder and queue a whole season.
- **Shows you the actual bitmaps.** Every cue is listed with the exact image
  the recognizer read, next to the text it produced.
- **Flags what to check.** Cues Vision was unsure about are marked. Fix them
  inline and the `.srt` updates as you type.
- **Names files sensibly.** `MyFilm.eng.srt`,
  `MyFilm.eng.english-sdh.srt`, `MyFilm.jpn.japanese-commentary.srt`.
- **Fits the Mac.** Open With in the Finder, a Services menu item, Open
  Recent, a Shortcuts action, notifications, Dock progress, drag an SRT
  straight out of the window.

### On Apple silicon Macs with Apple Intelligence

- **Clean Up** asks the on-device model to fix character-level recognition
  mistakes in flagged cues, and shows every change as a before/after you
  accept or reject. Nothing is applied on its own.
- **Translate…** exports a translated copy of a recognized track using the
  on-device Translation framework.

Both are hidden when unavailable. Neither sends anything off your Mac.

---

## Install

### Download the signed `.dmg`

Grab the latest `.dmg` from the
[Releases page](https://github.com/jeffalldridge/macSubtitleOCR-gui/releases/latest),
mount it, and drag the app to `/Applications`. It is signed with a Developer
ID and notarized by Apple, so it opens with no Gatekeeper warning.

### Build from source

```sh
git clone https://github.com/jeffalldridge/macSubtitleOCR-gui
cd macSubtitleOCR-gui
make app
open build/macSubtitleOCR-gui.app
```

Building needs Xcode 26 or newer. Running the app needs nothing but macOS.

---

## Requirements

- macOS 15 (Sequoia) or newer
- Apple silicon or Intel — the published `.dmg` is universal

Apple Intelligence clean-up needs macOS 26 with Apple Intelligence turned on.

---

## How it works

1. **Add files.** Drag them onto the window, use ⌘O, pick the app in the
   Finder's Open With menu, or select files in the Finder and choose
   Services ▸ Recognize Subtitles.
2. **Pick tracks.** The queue across the top of the window lists every file
   and, underneath it, every PGS and VobSub track with its language, cue
   count, and what it is doing. Tracks matching your language preference are
   ticked automatically.
3. **Choose where they go.** The toolbar says where subtitle files will land.
   Next to the film is the default; you can pick a folder, or have the app
   ask each time.
4. **Make subtitles.** Press the play button, or ⌘R. Progress counts real
   cues; the same button becomes Stop, and ⌘. does the same.
5. **Review.** The pane below the queue shows each cue's bitmap next to the
   recognized text. Flagged cues are the ones worth a look. Edit inline; the
   file is rewritten as you go. ⌘Z undoes.
6. **Mux.** The `.srt` files are already where you asked for them.

---

## Architecture

Two targets. The engine has no user interface and can be used on its own.

**`SubtitleEngine`**

| Piece | Job |
|---|---|
| `MKVReader` | Memory-mapped Matroska: probes `Info` and `Tracks` in milliseconds, then follows the file's own `Cues` index to the clusters holding a track instead of reading the whole film |
| `MatroskaCues` | The `Cues` index, found either before the clusters or through the `SeekHead` |
| `ContentCompression` | Undoes the frame compression remuxers apply to subtitle tracks, without which a track decodes to nothing |
| `PGSStream` | Indexes Blu-ray display sets without decoding, then decodes any cue on demand, compositing multi-object display sets |
| `VobSubStream` | The same for DVD subpictures, driven by the `.idx` |
| `IndexedBitmap` | Palette-indexed pixels, rendered either as they look on screen or as ink-on-paper for recognition |
| `TextRecognizer` | Apple Vision (`RecognizeTextRequest`) with per-line confidence |
| `TrackConverter` | Streams `indexed → progress → cue → finished` events, four cues at a time, cancellable |
| `SRTFile` / `SRTTiming` | SubRip rendering and parsing, and the rules that turn decoded timings into cue end times |

**`macSubtitleOCR-gui`**

`ConversionQueue` is the single source of truth: files, their tracks, the
options for this run, and the run itself. The window is a `VSplitView`: a
`Table` of files and their tracks on top, the cue review below it, and a
status bar that is always there. An inspector carries recognition and output
options. Every fixed measurement lives in `MainWindowLayout`, derived from the
columns and panes it has to hold rather than chosen by eye.

While a track is being recognized the next one is already being read, because
a subtitle track's blocks are spread across the whole film and recognition
needs the disk for nothing. Extracted MKV tracks are cached under
`~/Library/Caches`, so reopening a file is instant.

The design rationale is in
[`docs/specs/2026-09-09-v1-native-app-design.md`](docs/specs/2026-09-09-v1-native-app-design.md).
Build, notarization, and release mechanics are in
[`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## FAQ

### Do I still need MKVToolNix or Homebrew?

No. Versions up to 0.2 shelled out to `mkvmerge` and `mkvextract`. Version
1.0 reads Matroska itself, so the app is self-contained.

### How does this compare to Subtitle Edit?

[Subtitle Edit](https://github.com/SubtitleEdit/subtitleedit) is a far
broader tool — a full subtitle editor with format conversion, timing, and
much more. This app does one job: bitmap subtitles in, clean `.srt` out,
with a review pass. If you live in subtitle editing all day, use Subtitle
Edit. If you rip a disc now and then and want accurate SRTs to mux, this is
purpose-built for that.

### Why Apple Vision instead of Tesseract?

Vision consistently produces better OCR for bitmap subtitles, especially on
the small letter-shape cases (`l` vs `I`, accented characters, italics). The
upstream [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR) project
has benchmarks.

### Does it work with `.m2ts` Blu-ray streams?

Not directly. Demux to `.mkv` first, or rip with
[MakeMKV](https://www.makemkv.com/) — both keep the PGS streams intact.

### What about MP4?

MP4 is the *output* container in this workflow: mux the produced `.srt` as a
soft-sub track with [Subler](https://subler.org). MP4 essentially never
carries PGS as input, so it is not a supported input.

### Is recognition perfect?

No. It is very good, and the review screen exists because the last few
percent matter. Italics, very small type, and decorative faces in musicals or
animation are the usual trouble. Flagged cues are where to look first.

### Where do my SRT files go?

Next to the film by default, so `~/Movies/MyFilm.mkv` produces
`~/Movies/MyFilm.eng.srt`. The toolbar menu next to the play button changes
that: pick a folder, or choose *Ask each time* and a folder chooser appears
before each run. Track names are folded into the filename, so SDH, commentary,
and sing-along variants never collide.

### Does anything leave my Mac?

Only the once-a-day update check, which asks GitHub for the latest release
tag and nothing else. Turn it off in Settings. Recognition, clean-up, and
translation all run locally.

---

## Troubleshooting

**A track fails with "not a Matroska file."** The file is not a Matroska
container, or its header is damaged. Re-rip with
[MakeMKV](https://www.makemkv.com/).

**Recognition returns nonsense for one track.** Turn on *Invert images
before recognition* in the inspector and run that track again. Dark-on-light
captions sometimes need it.

**Names are consistently misread.** Add them to *Custom words* in the
inspector; the recognizer will prefer them.

**A file has subtitles but no tracks appear.** The tracks are probably text
subtitles (SRT, ASS) rather than bitmaps — the file detail says so. Text
subtitles do not need recognition; extract them with any Matroska tool.

**Right-click → Open on first launch.** Should not happen: the published
`.dmg` is signed and notarized. If you see it, you are running a build from
source, or the download was altered — check the SHA256 against the
`SHA256SUMS.txt` published with the release.

---

## Contributing

Pull requests welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for setup,
the test and build checklist, and what kinds of change fit the project. For
security issues, see [`SECURITY.md`](SECURITY.md) — please don't open public
issues for those.

---

## Credits

The PGS and VobSub decoders and the Vision recognition pipeline are derived
from [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR) by **Ethan
Dye**, MIT-licensed. That project did the hard work of getting bitmap
subtitle decoding right on macOS; this app carries it into a native
interface. What changed in the port is recorded in
[`Sources/SubtitleEngine/UPSTREAM.md`](Sources/SubtitleEngine/UPSTREAM.md),
and full license texts are in
[`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md) and the app's
Acknowledgements window.

Recognition and translation are Apple's Vision, Translation, and Foundation
Models frameworks. Test fixtures are excerpts of *Sintel* © Blender
Foundation, CC BY 3.0.

MIT licensed. See [`LICENSE`](LICENSE).

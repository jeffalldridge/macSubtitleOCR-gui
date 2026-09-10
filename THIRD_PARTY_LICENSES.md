# Third-Party Licenses

This project incorporates or attributes the following third-party work. Each
is used under the terms of its own license. The same information is available
inside the app under Help ▸ Acknowledgements.

## Incorporated into the app

### macSubtitleOCR

- **Source:** https://github.com/ecdye/macSubtitleOCR
- **License:** MIT
- **Author:** Ethan Dye
- **What we do with it:** `Sources/SubtitleEngine/` is derived from this
  project. The Matroska reading, PGS and VobSub decoding, and Vision
  recognition pipeline all began as upstream source, ported to run in-process
  as a library rather than as a command-line tool. The port is documented file
  by file in
  [`Sources/SubtitleEngine/UPSTREAM.md`](Sources/SubtitleEngine/UPSTREAM.md),
  including the upstream commit it was taken from and every behavioral change.

  Earlier releases of this app (0.1 and 0.2) instead bundled the upstream
  command-line binary unmodified.

```
The MIT License (MIT)

Copyright © 2024-2026 Ethan Dye

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Apple SF Symbol "captions.bubble"

- **Source:** Apple SF Symbols
- **License:** Apple's SF Symbols License Agreement — use within apps is
  permitted; standalone redistribution is not.
- **What we do with it:** the app icon composes this symbol as one layer of an
  Icon Composer document. The SVG is in `Resources/AppIcon.icon/Assets/`.

## Apple frameworks (part of macOS, not redistributed)

| Framework | Used for |
|---|---|
| Vision | Text recognition (`RecognizeTextRequest`) |
| Translation | Optional on-device translation export |
| FoundationModels | Optional Apple Intelligence clean-up suggestions (macOS 26) |
| AppIntents | The "Recognize Subtitles" Shortcuts action |
| TipKit, UserNotifications, AppKit, SwiftUI, CryptoKit | Interface and system integration |

## Test fixtures (not shipped in the app)

### Sintel

- **Source:** https://durian.blender.org
- **License:** CC BY 3.0
- **Author:** Blender Foundation
- **What we do with it:** `Tests/SubtitleEngineTests/Fixtures/sintel.*`
  contains short subtitle excerpts of the open movie *Sintel*, taken from the
  upstream macSubtitleOCR test corpus. They are used only by the automated
  tests and are not part of the distributed app.

## No longer used

### MKVToolNix (`mkvmerge`, `mkvextract`)

- **License:** GPL-2.0-or-later
- Releases 0.1 and 0.2 called the user's own Homebrew-installed MKVToolNix at
  runtime to list and extract Matroska tracks. They were never bundled. Since
  1.0 the app parses Matroska itself and does not use MKVToolNix at all.

## What is this project's own work

The SwiftUI interface, the queue and review model, the cue review experience,
the in-process restructuring of the engine (indexed streams, random-access
decoding, progress and cancellation, multi-object compositing, the timing
rules), Matroska probing and extraction over a memory-mapped buffer, output
naming, the stream cache, packaging and notarization, and the icon design.

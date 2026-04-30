# Third-Party Licenses

This project bundles, depends on, or attributes the following third-party
software. Each is used under the terms of its own license.

## Bundled inside the `.app`

### macSubtitleOCR

- **Source:** https://github.com/ecdye/macSubtitleOCR
- **License:** MIT
- **Author:** Ethan Dye
- **What we do with it:** the upstream macSubtitleOCR command-line binary
  is compiled from the pinned git submodule at `Vendor/macSubtitleOCR/` and
  embedded inside this app's bundle as `Contents/Resources/macSubtitleOCR`.
  This app is a SwiftUI front-end that invokes the upstream binary; all OCR
  intelligence belongs to the upstream project.

```
The MIT License (MIT)

Copyright © 2024-2026 Ethan Dye

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction… (full text in
Vendor/macSubtitleOCR/LICENSE.md)
```

### Apple SF Symbol "captions.bubble"

- **Source:** Apple SF Symbols
- **License:** Apple's SF Symbols License Agreement (use within apps permitted;
  standalone redistribution prohibited)
- **What we do with it:** the app icon composition uses the `captions.bubble`
  symbol as one layer in an Icon Composer document. The SVG is included in
  `Resources/icon.icon/Assets/`. This use is permitted under Apple's terms.

## Runtime dependencies (not bundled)

### MKVToolNix (`mkvmerge`, `mkvextract`)

- **Source:** https://mkvtoolnix.download/
- **License:** GPL-2.0-or-later
- **Author:** Moritz Bunkus and contributors
- **What we do with it:** at runtime, this app shells out to `mkvmerge -J` to
  list subtitle tracks in MKV files, and to `mkvextract` to pull a single
  track to a temporary `.sup` file before OCR. **MKVToolNix is not bundled
  with this app.** Users install it themselves via Homebrew
  (`brew install mkvtoolnix`); the app surfaces a one-tap install card if it
  is missing. Because we do not redistribute MKVToolNix binaries, the GPL's
  copyleft terms do not bind this project's source code.

### Apple Vision framework

- **License:** Apple platform binary
- **What we do with it:** macSubtitleOCR uses Apple's Vision framework for
  the actual text recognition. The framework is part of macOS; we do not
  redistribute it.

## Build-time dependencies (not bundled or shipped)

### dylibbundler (legacy build tooling)

Earlier development versions of this project bundled MKVToolNix into the
`.app` and used `dylibbundler` to relocate dynamic libraries. The current
public release does **not** bundle MKVToolNix (see above), so `dylibbundler`
is no longer required. The historical commits remain in git history.

### MKVToolNix and dylibbundler at build time

Neither tool is required to build this app any longer. Earlier in the
project's history they were used to assemble a self-contained `.app`; the
current public release relies on the user's own Homebrew-installed MKVToolNix
at runtime.

## Notes on attribution

- The upstream macSubtitleOCR README is the canonical source for OCR-engine
  behavior; this project is a thin SwiftUI wrapper.
- Subtitle decoding (PGS, VobSub) and OCR pipelines are upstream's work.
- The contributions of this project are: the SwiftUI interface, multi-track
  selection, language-aware filenames, persistent options, the SRT preview,
  the Makefile + .app assembly + notarization workflow, and the icon design.

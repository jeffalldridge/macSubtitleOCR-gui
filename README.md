# macSubtitleOCR-gui

A polished macOS SwiftUI front end for [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR).
Drop a `.mkv`, `.sup`, `.sub`, or `.idx` file, pick a PGS/VobSub track, get a clean `.srt` next to it.

## Requirements

- macOS 14+
- Swift 6 toolchain (Xcode 16+ or Swift.org toolchain)
- `mkvtoolnix` (`brew install mkvtoolnix`)

## Build

```sh
make build      # compiles upstream macSubtitleOCR + this app
make run        # builds and runs from terminal
make app        # builds a real .app bundle in build/
```

## Update upstream tool

```sh
make update     # bumps the macSubtitleOCR submodule and rebuilds
```

See [docs/superpowers/specs/](docs/superpowers/specs/) for the design rationale.

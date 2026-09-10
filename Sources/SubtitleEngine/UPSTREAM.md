# Engine provenance

`SubtitleEngine` is derived from [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR)
by Ethan Dye, MIT License. It was ported from upstream commit
`e55caf7be3482715bfd72d152c9cb13e33084281` (main, September 2026) and then
adapted for use as an in-process library. The upstream license text is in
`THIRD_PARTY_LICENSES.md` at the repository root and in the app's
Acknowledgements window.

## What was ported

| Upstream file | Here | Notes |
|---|---|---|
| `MKV/EBML/*.swift`, `MKV/MKVFileHandler.swift`, `MKV/MKVTrackParser.swift`, `MKV/MKVHelpers.swift` | `Container/EBMLReader.swift`, `Container/MKVReader.swift`, `Container/MKVBlock.swift` | Rewritten over a memory-mapped buffer instead of `FileHandle`. Reads the whole `TrackEntry` (name, default/forced flags, BCP 47 language), honors `TimestampScale`, handles unknown-size clusters and block lacing. The PGS and VobSub re-wrapping of Matroska blocks is kept as upstream wrote it. |
| `Subtitles/PGS/PGS.swift`, `Parsers/ODS.swift`, `Parsers/PDS.swift`, `RLE/RLEData.swift` (`decodePGS`) | `PGS/PGSSegments.swift`, `PGS/PGSRLE.swift`, `PGS/PGSStream.swift` | Split into an index pass (no RLE decoding) and per-cue decoding for random access. Parses PCS composition objects so display sets with several objects are composited at their positions; uses the palette the PCS references; palette-only updates no longer end a cue. |
| `Subtitles/VobSub/*.swift`, `RLE/RLEData.swift` (`decodeVobSub`) | `VobSub/VobSubIDX.swift`, `VobSub/VobSubPacket.swift`, `VobSub/VobSubRLE.swift`, `VobSub/VobSubStream.swift` | Same decoder, exposed as an indexed stream with per-cue decoding. |
| `Subtitles/Subtitle.swift` (`SubtitleImageSource`) | `Bitmap/IndexedBitmap.swift` | Adds a display rendering (original colors, transparent background) alongside the recognition rendering. |
| `Subtitles/SubtitleProcessor.swift` | `Recognition/TextRecognizer.swift`, `Conversion/TrackConverter.swift` | macOS 15 Vision API only; bounded task group instead of a polling semaphore; streaming progress events; cancellation; keeps the English `l → I` correction. |
| `Subtitles/SRT/SRT.swift` | `SRT/SRTFile.swift`, `SRT/SRTTiming.swift` | Adds a parser. End times: decoded end is kept (clamped to the next cue) instead of always capped at five seconds; the five-second cap applies only when the end is unknown. |
| `Extensions/*.swift` | `Support/BinaryReading.swift` | Only the pieces still needed. |

Not ported: the command-line front end (`macSubtitleOCR.swift`,
`macSubtitleOCROptions.swift`), JSON output, PNG dumping, the optional FFmpeg
decoder, and `swift-argument-parser`.

## Written here, with no upstream counterpart

| Here | Why |
|---|---|
| `Container/MatroskaCues.swift` | Reads the file's `Cues` index, so pulling one subtitle track out of a 30 GB remux touches the clusters that hold it rather than the whole file. Found either before the clusters or through the `SeekHead`. An index that names clusters but yields no subtitles is treated as stale and the file is read in full instead. |
| `Container/ContentCompression.swift` | Matroska `ContentEncodings`. Remuxers routinely deflate subtitle frames, and without this the decoder is handed compressed bytes and finds nothing at all. Handles zlib (algorithm 0) and header stripping (algorithm 3); an encrypted track is reported rather than silently empty. |
| `extract(trackNumbers:orAlso:)` in `MKVReader+Extract.swift` | Whether the index helps and where the blocks are is one question, asked once. When the index cannot reach a track, every track costs a full pass, so the others are taken in the same pass. |
| `VobSubPacket.timing(_:offset:nextOffset:)` | Building the cue list reads only the control block at the end of each subpicture. Upstream reassembles the whole subpicture to read its timings and then does it again to draw one. |

## Behaviour that differs from upstream

These are fixes, not preferences. Each has a test.

- **Timestamp conversion.** Nanoseconds to 90 kHz ticks multiplies before it
  divides. Dividing first quantizes every timestamp to nine-tick steps for any
  `TimestampScale` that is not a multiple of 100 000.
- **Palette-only display sets.** A PGS composition that only updates the
  palette no longer ends the open cue, which used to produce empty cues.
- **Unknown-size elements** resolve iteratively; the recursive form overflowed
  the stack on a 120 KB file.
- **Values read from a file saturate rather than trap** — track numbers,
  cluster timestamps, timestamp scales, `.idx` timestamps, SRT hours, and PGS
  object dimensions. A crafted file makes a bad subtitle, not a crash.
- **`Data.mapped` maps unconditionally on local volumes.** Foundation's
  "if safe" declines on most external drives, and declining means copying the
  file into memory: 58.7 seconds and 1.4 GB on a 30 GB remux, against 0.011
  seconds and 6 MB. Files on network shares are read rather than mapped,
  because there every page fault is a round trip and a dropped share raises a
  signal nothing can catch.

## Keeping up with upstream

```sh
make diff-upstream                # diffs the ported files against upstream main
make diff-upstream REF=v1.1.0     # …or against a specific ref
```

Upstream changes to the decoders are worth merging by hand; changes to the
CLI or FFmpeg path are not relevant here.

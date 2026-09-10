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

## Keeping up with upstream

```sh
make diff-upstream                # diffs the ported files against upstream main
make diff-upstream REF=v1.1.0     # …or against a specific ref
```

Upstream changes to the decoders are worth merging by hand; changes to the
CLI or FFmpeg path are not relevant here.

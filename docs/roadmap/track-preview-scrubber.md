# Roadmap — Track Preview & Scrubber

**Status: delivered in 1.0, in a simpler form than proposed.**

This document proposed a bitmap timeline with a scrubber, disk caching, and
an OCR overlay, in six phases estimated at 28–39 hours. Version 1.0 ships the
substance of it by a shorter route:

| Proposed | Shipped in 1.0 |
|---|---|
| Vendor the PGS parser for random-access decoding | The whole engine is in-process; `PGSStream` and `VobSubStream` index cheaply and decode any cue on demand |
| Bitmap timeline with a scrubber and keyboard transport | A cue table: every cue with its bitmap, timing, and text, navigable with the arrow keys and searchable |
| Large preview pane with pinch-zoom | A full-size preview of the selected cue above the list |
| OCR text overlaid on each frame | Recognized text sits beside each bitmap, and is editable in place |
| Mark cues for re-OCR | Better: edit the cue directly, or ask Apple Intelligence for a suggestion |
| Disk-cached preview index for instant reopening | Extracted tracks are cached under `~/Library/Caches`, keyed by path, size, modification date, and track |
| Cue density heatmap, skip-cues-from-output, PNG export | Not shipped. Nobody has asked; revisit if that changes. |

What the original document got right is worth keeping in mind: the value is in
*seeing the bitmap next to the text*, and the second open of a file has to be
instant. Both hold.

The full original proposal is in the git history if the unshipped ideas ever
become interesting.

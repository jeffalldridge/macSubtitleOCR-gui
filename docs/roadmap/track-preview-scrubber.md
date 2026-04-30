# Roadmap — Track Preview & Scrubber (Path 3)

**Status:** Proposed (no implementation yet)
**Author:** Jeff Alldridge (with Claude)
**Last updated:** 2026-04-30
**Estimated total effort:** 28–39 hours of focused work — call it 2–3 calendar weeks at a couple hours a day
**Dependencies:** the existing track-extraction pipeline, the upstream macSubtitleOCR PGS parser source

---

## 1. Vision

After picking a track in the **Tracks** screen, an inline **Preview** panel reveals a real bitmap timeline of every cue in that track — the *exact* image the OCR engine will read. The user can scrub with the keyboard, mouse, or trackpad; pinch-zoom into hard cues; mark cues to skip; and pivot directly into the OCR run with confidence that they picked the right track and got the framing right.

Once OCR finishes, the same scrubber comes back with the OCR'd text overlaid on each frame, so the user can spot bad cues before muxing.

The bar this needs to clear: **scrubbing through a 3,000-cue Wonka track on an M-series Mac feels as smooth as scrubbing a video timeline in Final Cut.**

---

## 2. Why it matters

| User pain today | What the preview fixes |
|---|---|
| "Is this *actually* the English SDH track or just standard subs?" | Skim the bitmaps in 3 seconds, see hearing-impaired cues like `[door slams]`. |
| "Wonka has 15 PGS tracks; commentary tracks alone are 800 cues. Which one is the director?" | Read a few cues; commentary is plain text on otherwise empty frames. |
| "OCR took 4 minutes on the wrong track" | Decide *before* spending OCR time. |
| "OCR'd this last week, do I need to redo it?" | Disk-cached preview index opens instantly the second time. |
| "One cue OCR'd wrong, do I redo the whole track?" | Future: re-OCR a single cue from the preview panel. |

The killer use case is the multi-track UHD remux (Moana: 28 PGS tracks). Without a preview, the user is doing a "trust the metadata or run OCR and see" gamble. With it, the call is obvious.

---

## 3. What "great" looks like

A user dragging a Wonka MKV in:

1. Drop file → Tracks screen lists 15 PGS tracks (already works).
2. Click "English (SDH)". A panel slides in below the list:
   - **Left:** vertical cue list showing time and the first ~40 chars of OCR text (or "—" before OCR runs).
   - **Right:** large bitmap of the current cue at 1:1 with letterboxing. Above it, a horizontal timeline ribbon showing every cue as a tiny tick mark (denser where dialogue clusters).
   - **Bottom:** transport bar — `← →` step, `Shift+← →` jump 10, J/K/L for hold-and-step, time scrubber, "Frame 47 of 932" counter.
3. Pinch-zoom on the bitmap to inspect a hard glyph.
4. Click "Run OCR". The panel stays open; bitmaps are now annotated with the OCR'd text underneath. Bad cue at 0:31:14 ("fiowing")? Right-click → "Mark for re-OCR" — that cue gets queued for a second pass with `--invert` or with custom words tuned by the user.
5. Hit Cmd-W. Reopen the MKV next week — the disk-cached preview index loads instantly; no re-extraction.

That last point — **the second open is instant** — is the difference between "useful" and "magical."

---

## 4. Phases

Each phase ships working software. Stop after any phase if priorities shift; later phases assume earlier ones land.

### Phase 1 — Decoder foundation (6–8 hrs)

Goal: a Swift type that, given a `.sup` file, returns an indexed list of cues with random-access frame decoding.

**Work:**

- Vendor the upstream PGS parser into our app under `Sources/macSubtitleOCR-gui/PGS/`:
  - `PGS.swift`, `Parsers/PCS.swift` / `WDS.swift` / `PDS.swift` / `ODS.swift`, `RLE/RLEData.swift`
  - The five tiny `Extensions/` files (`BinaryIntegerExtensions`, `CollectionExtensions`, `DataExtensions`, etc.)
  - Total: ~720 lines, single self-contained module
  - Strip the OCR/Vision-specific bits — we only need parse and decode-to-bitmap
- Define the `PGSReader` API:
  ```swift
  public struct PGSReader: Sendable {
      public init(source: URL) throws
      public var cueCount: Int { get }
      public var duration: CMTime { get }
      public func cue(at index: Int) -> CueIndexEntry  // metadata only — fast
      public func render(at index: Int) async throws -> CueFrame  // decodes + RLE + composes
  }
  public struct CueIndexEntry: Sendable {
      public let index: Int
      public let presentationTime: CMTime
      public let endTime: CMTime
      public let byteOffset: Int64  // for caching
  }
  public struct CueFrame: Sendable {
      public let index: Int
      public let image: CGImage
      public let canvasSize: CGSize  // 1920×1080 etc.
      public let cropRect: CGRect    // where the bitmap actually sits
  }
  ```
- The reader **builds a cheap index pass** at init (one full file walk, no RLE decoding) so we know cue count and timestamps up front — fast even on 5,000-cue tracks.
- Decoding any single cue is on-demand and cached in an `NSCache` keyed by `cueIndex`.
- Write tests against `Vendor/macSubtitleOCR/Tests/Resources/sintel.sup`:
  - `cueCount` matches expected
  - `cue(at: 0).presentationTime` matches expected
  - `render(at: 0).image` is a non-nil `CGImage` of expected size
  - `render(at: cueCount - 1)` works (random access)

**Acceptance:** `swift test` shows new PGSReader tests passing. No new runtime deps. Decoder is pure-function and has no UI dependencies.

**Deliverable:** a commit that other phases can build on without UI risk.

---

### Phase 2 — Preview UI primitives (6–8 hrs)

Goal: a self-contained `TrackPreviewView` that takes a `PGSReader` and renders the experience described in §3.

**Work:**

- `TrackPreviewView` (SwiftUI):
  - Top: cue ribbon (tick marks) — `Canvas` drawing pass keyed on `cueCount`. Each tick is a 1-pixel vertical line; current cue highlighted in accent color.
  - Center: large bitmap area. `Image(cgImage:)` with `.resizable()`. Letterboxes inside available space.
  - Left rail: cue list with timestamp + OCR text snippet (if available). `LazyVStack` inside `ScrollView` for performance with 5,000 cues.
  - Bottom: transport bar — step, jump, scrub, counter, time display.
- `TrackPreviewModel` (`@Observable`):
  - Holds the active `PGSReader`, current cue index, frame cache hit-rate, recent decodes.
  - Pre-decodes ±5 cues around the current index in a low-priority Task.
  - Exposes `step(by:)`, `seek(to:)`, `jumpTo(time:)`.
- Keyboard navigation:
  - `←` / `→` = step ±1
  - `Shift+←` / `Shift+→` = jump ±10
  - `Home` / `End` = first / last
  - `Space` = toggle "play" mode (advance every 250ms)
- Pinch-to-zoom on the bitmap area (`MagnificationGesture`) up to 4×.

**Acceptance:** preview view renders correctly when given a `PGSReader` and an empty cue-text dictionary. Keyboard shortcuts work in a smoke test. SwiftUI canvas of 5,000 ticks doesn't drop frames during scrubbing on an M-series machine. Test coverage on the model's state machine (step/seek/jump bounds).

**Deliverable:** a commit that adds `TrackPreviewView` + `TrackPreviewModel` but doesn't yet integrate them into the main flow.

---

### Phase 3 — Integration with the existing pipeline (4–6 hrs)

Goal: the user clicks a track in `TracksView`, an inline preview slides in.

**Work:**

- Extend `SubtitleJob` with:
  ```swift
  public var previewReader: PGSReader?
  public var previewModel: TrackPreviewModel?
  public var previewLoadingTrack: Track.ID?
  ```
- New phase transition in `TracksView`: when the user **first** ticks a track, kick off:
  1. `MKVToolNixExtractor.extract(...)` for that track (we already have this — it produces a temp `.sup`)
  2. `PGSReader(source: extractedSUP)` — builds the index
  3. Hand the reader to a fresh `TrackPreviewModel`
- Cache extracted `.sup` files keyed by `(input file path, file mtime, track id)` in `~/Library/Caches/com.tentstudios.macSubtitleOCR-gui/`. Second open of the same file + track skips the extraction.
- Multi-track preview: when the user has multiple tracks ticked, the preview area gets a small **track selector** (pill row) so they can switch between previews without re-extracting. We keep up to 3 readers warm; the rest are lazily evicted.
- Preview is collapsible (default open when 1 track ticked, default collapsed when many).

**Acceptance:** drop the sintel fixture → tick the only track → preview appears within 1s, cue count matches, scrubbing works. Drop Wonka → tick "English (SDH)" → preview appears within 5s on first open, <500ms on second open. Tick another Wonka track → tab switches; previously-seen preview comes back instantly.

**Deliverable:** a commit that wires preview into the main flow. Manual smoke test against Moana + Wonka.

---

### Phase 4 — Polish & performance (6–8 hrs)

Goal: feels native-app smooth, not "lab demo."

**Work:**

- Disk cache for decoded frames (pacing: only cache the index + the current ±50 cues). Keyed by `(file_hash, track_id, cue_index)`. Stored as PNG. Bounded to ~200MB; LRU evicted.
- Pre-decode strategy: while user is paused on cue N, opportunistically decode N±10 in background Tasks. Cancel on next seek.
- Memory budget: cap the in-memory cache at ~50 cues (PGS frames are large — 1920×1080 RGBA is ~8MB each).
- Smooth scrubber drag: throttle decode requests to one per 30ms while dragging; fall back to "show the nearest already-decoded cue" while scrubbing fast.
- Tick ribbon performance: at 5,000 cues, the SwiftUI Canvas pass needs to be a single `Path` build, not 5,000 sub-shapes. Verify with Instruments.
- App launch time budget: opening the app with no file should still be <0.5s. Don't eagerly load anything from previous session except the cache index.

**Acceptance:** scrubbing through a 3,000-cue track at full drag speed never drops below 30fps in Instruments' SwiftUI profiler. Memory stays under 250MB during preview. Disk cache footprint stays bounded. No regressions in the existing 40 tests.

**Deliverable:** a commit that's profiled and tuned. Notes on any tradeoffs land in `CLAUDE.md`.

---

### Phase 5 — Quality features (4–6 hrs)

Goal: the things that turn "great" into "people want to share screenshots."

Pick the subset that matches your workflow; this phase is opt-in à la carte.

| Feature | Effort | User value |
|---|---|---|
| **OCR overlay on bitmap** — once the OCR run completes, each cue's preview shows the recognized text underneath the bitmap; bad ones are obvious | 1 hr | High |
| **Mark cues for re-OCR** — right-click a cue, queue it for a second pass (different `--invert` or custom words). After re-run, the new text replaces the bad one in the SRT | 2 hr | Medium |
| **Skip cues from output** — checkbox per cue to exclude from the SRT (great for cutting forced studio logos, language warnings) | 1 hr | Medium |
| **Export current frame as PNG** — debug aid for filing upstream issues | 0.5 hr | Low |
| **Cue density heatmap** in the timeline ribbon — peaks where dialogue clusters | 1 hr | Low |
| **Side-by-side bitmap vs. cleaned bitmap** when `--invert` is on | 1 hr | Low |

Pick 2–3 of these to ship. Skip the rest.

**Acceptance:** each chosen feature has at least one test. UX writer pass on labels and tooltips.

---

### Phase 6 — Documentation & smoke tests (2–3 hrs)

Goal: someone (you next year, me, or a contributor) can pick this up cold.

**Work:**

- README: new "Preview" section with screenshot of Wonka in the scrubber.
- `CLAUDE.md`: note the cache location, the eviction policy, and which classes own which state.
- A short doc at `docs/architecture/track-preview.md` covering the data flow from drop → extract → index → render.
- Manual smoke test plan documented (drop test fixtures, scrub, run OCR, verify overlay).
- A `Tests/` fixture: one short `.sup` (~10 cues) checked in, used for snapshot-style testing of the model's state transitions.

**Acceptance:** README has a screenshot. `CLAUDE.md` reflects the new architecture. Tests run green.

---

## 5. Architecture sketch

```
       ┌──────────────────────────────────────────────────────────┐
       │                       SubtitleJob                         │
       │   input:URL  tracks:[Track]  selectedTrackIDs  options    │
       │   previewReader   previewModel   previewLoadingTrack      │
       └────────────────┬───────────────────┬─────────────────────┘
                        │                   │
                        ▼                   ▼
        ┌─────────────────────┐    ┌──────────────────────┐
        │   TrackProber       │    │  TrackPreviewModel   │
        │  (mkvmerge -J)      │    │  current index       │
        └─────────────────────┘    │  pre-decode lookahead│
                                   │  pinch zoom          │
                                   └──────────┬───────────┘
                                              │ uses
                                              ▼
                                   ┌──────────────────────┐
                                   │     PGSReader        │
                                   │  cue index           │
                                   │  render(at:)         │
                                   │  in-memory NSCache   │
                                   │  disk cache (~/Lib…) │
                                   └──────────┬───────────┘
                                              │ wraps
                                              ▼
                                  ┌────────────────────────┐
                                  │  Vendored PGS decoder  │
                                  │  (PGS, RLE, Parsers)   │
                                  └────────────────────────┘
```

`PGSReader` and `TrackPreviewModel` are intentionally split:
- `PGSReader` is **pure data** — given a file, give me cues. No SwiftUI, no observation, fully testable.
- `TrackPreviewModel` is **UI state** — current index, zoom, playback. Owns the reader.

`TrackPreviewView` reads from the model only. The model can be replaced (e.g., a `MockTrackPreviewModel` for SwiftUI Previews).

---

## 6. Risks & open questions

| Risk | Mitigation |
|---|---|
| **Vendored PGS decoder drifts from upstream.** | Vendor only the parser core; leave a `VENDORED.md` listing the upstream commit hash + file paths. `make update` does NOT touch our vendored copy — keep it manual so a contributor sees the diff. Re-vendor when upstream PGS code changes (rare). |
| **Disk cache invalidation is hard.** | Key on `(file_hash_first_1MB + size + track_id)`. Don't try to be perfect; cache misses are cheap (re-extract). |
| **5,000-cue scrubber tanks SwiftUI.** | Verify with Instruments early in Phase 4. Fallback: render ticks via `Canvas` with a single `Path`, or downsample to 500 ticks visually with a "more cues here" hover. |
| **PGS decoder bugs on weird sources.** | Use the existing macSubtitleOCR test fixtures (sintel.sup) as our test corpus. Add Wonka + Moana fixtures (small extracted slices) as regression tests. |
| **Memory blows up on 8MB-per-frame caching.** | Hard cap the in-memory cache at 50 frames (~400MB). Disk cache PNGs (compressed). Don't cache uncompressed bitmaps. |
| **Multi-track preview becomes confusing UI.** | Phase 3 ships single-preview-at-a-time with a track switcher pill row. Resist the urge to do split-pane or carousel until users ask. |
| **Phase 5 features tempt scope creep.** | Strict: pick 2–3 max. The rest go in a "future" doc. |

**Open questions for you to decide before Phase 1 starts:**

1. **Vendor vs. fork.** I propose vendoring (copy files into our repo). Alternative: fork upstream, make PGS a library product, depend on the fork. Vendoring is simpler and isolates us from upstream churn but creates a maintenance debt. *My recommendation: vendor for now. Re-evaluate if upstream's PGS code gets meaningful updates.*
2. **Cache location.** `~/Library/Caches/com.tentstudios.macSubtitleOCR-gui/` is the macOS-correct place — Time Machine excludes it, the system can purge it under disk pressure. Confirm we want this vs. somewhere durable.
3. **Phase 5 picks.** Decide upfront which 2–3 features. My picks: **OCR overlay**, **Skip cues from output**, **Cue density heatmap**.
4. **Multi-track preview UI.** Pill row of selected tracks with active highlight, vs. tab bar, vs. dropdown. *Recommend pill row.*
5. **Preview always-on or opt-in?** Default-show when only 1 track is ticked, default-collapsed when 2+. Confirm.

---

## 7. Scope cuts if you want to compress

If you'd rather hit "good" in a week and skip "magical":

| Cut | Saves | Cost |
|---|---|---|
| Skip Phase 4 polish | 6–8 hrs | Scrubbing isn't smooth on 3,000-cue tracks; memory footprint is sloppy |
| Skip Phase 5 entirely | 4–6 hrs | No OCR overlay, no cue exclusion, no heatmap |
| Skip disk cache (memory only) | 2 hrs | Re-opening Wonka next week takes 5s instead of instant |
| Single-track preview only (drop multi-track switching) | 2 hrs | Have to un-tick / re-tick to compare two tracks |
| Drop pinch-zoom | 1 hr | Hard cues are harder to read |

**Minimum viable preview = Phases 1–3 only**, ~16–22 hrs. Buys you a real bitmap timeline with keyboard navigation, single-track-at-a-time. The Wonka use case works; the magic is missing but the function is there.

---

## 8. Decision points & next steps

To kick this off I need from you:

1. **Approve the phase breakdown** — or push back on any phase as too big or too small.
2. **Answer the 5 open questions in §6** — especially the Phase 5 picks and the multi-track UI.
3. **Confirm scope** — full Path 3 (~30+ hrs) or compressed (Phases 1–3, ~20 hrs).
4. **Greenlight Phase 1.** I'd start with the decoder vendoring + tests in a single PR/commit, since it's the foundation for everything else and has no UI risk.

Once Phase 1 lands, I'd write a real spec at `docs/superpowers/specs/<date>-track-preview-phase-N.md` per phase as we go, following the same flow we used for the original app — brainstorm → spec → plan → implement.

---

## Appendix A — Estimated cost at a glance

| Phase | Hours | Cumulative | Ship checkpoint |
|---|---|---|---|
| 1 — Decoder | 6–8 | 6–8 | Tests pass; no UI yet |
| 2 — Preview UI primitives | 6–8 | 12–16 | Scrubber view works in isolation |
| 3 — Integration | 4–6 | 16–22 | **Minimum viable preview** |
| 4 — Polish & perf | 6–8 | 22–30 | Smooth on 3,000+ cue tracks |
| 5 — Quality features (à la carte) | 4–6 | 26–36 | Pick 2–3 |
| 6 — Docs & smoke tests | 2–3 | 28–39 | Ship |

---

## Appendix B — Out of scope (deliberately)

- VobSub preview. Not on the path; revisit if anyone asks.
- Editing OCR text inline. The user re-OCRs or hand-edits in their SRT editor of choice.
- Real-time playback with audio sync. This isn't a video player; we're previewing subtitle bitmaps only.
- macSubtitleOCR upstream PRs. Vendoring is the path forward; we don't gate on upstream merges.
- Cross-platform (iOS / Linux). macOS only.
- Code signing / notarization with Developer ID. Still ad-hoc; same as today.

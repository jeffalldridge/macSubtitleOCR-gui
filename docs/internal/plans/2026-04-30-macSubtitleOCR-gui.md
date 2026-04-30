# macSubtitleOCR-gui Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a polished SwiftUI macOS app that wraps macSubtitleOCR — drop a video/subtitle file, pick a PGS or VobSub track, get a clean SRT next to it.

**Architecture:** SwiftPM-driven SwiftUI executable. macSubtitleOCR is vendored as a git submodule under `Vendor/`; a `Makefile` builds it and copies the binary into our package's `Resources/`. Six small components (`TrackProber`, `TrackExtractor`, `OCRRunner`, `SRTFinalizer`, `BundledBinary`, `ToolchainProbe`) sit behind a single `@Observable SubtitleJob` state container that drives a four-phase UI (`Drop → Tracks → Progress → Done`).

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`import Testing`), SwiftPM, macOS 14+, MKVToolNix (`mkvmerge`/`mkvextract` via brew, runtime dep), git submodule for upstream macSubtitleOCR.

---

## File Structure

| Path | Purpose |
|---|---|
| `Package.swift` | SwiftPM manifest, executable target + test target |
| `Makefile` | Build, run, update, clean, package as `.app` |
| `.gitignore` / `.gitmodules` | VCS hygiene |
| `README.md` | User-facing docs |
| `CLAUDE.md` | Repo instructions for future Claude sessions |
| `Vendor/macSubtitleOCR/` | git submodule |
| `Sources/macSubtitleOCR-gui/App.swift` | `@main`, `App` + `WindowGroup` |
| `Sources/macSubtitleOCR-gui/AppView.swift` | Phase router |
| `Sources/macSubtitleOCR-gui/SubtitleJob.swift` | Observable state container |
| `Sources/macSubtitleOCR-gui/Probing/Track.swift` | Track value type |
| `Sources/macSubtitleOCR-gui/Probing/TrackProber.swift` | mkvmerge JSON parsing |
| `Sources/macSubtitleOCR-gui/Probing/ToolchainProbe.swift` | Locate `mkvmerge`/`mkvextract` |
| `Sources/macSubtitleOCR-gui/Extraction/TrackExtractor.swift` | Protocol |
| `Sources/macSubtitleOCR-gui/Extraction/MKVToolNixExtractor.swift` | `mkvextract` impl |
| `Sources/macSubtitleOCR-gui/OCR/BundledBinary.swift` | Locate the macSubtitleOCR binary |
| `Sources/macSubtitleOCR-gui/OCR/OCRRunner.swift` | Process invocation, progress |
| `Sources/macSubtitleOCR-gui/Finalize/SRTFinalizer.swift` | Output filename rules |
| `Sources/macSubtitleOCR-gui/Views/DropView.swift` | File drop + picker |
| `Sources/macSubtitleOCR-gui/Views/TracksView.swift` | Track selection + options |
| `Sources/macSubtitleOCR-gui/Views/RunView.swift` | Progress + cancel + log |
| `Sources/macSubtitleOCR-gui/Views/DoneView.swift` | Success / error final state |
| `Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR` | Embedded binary (gitignored, written by Makefile) |
| `Tests/macSubtitleOCR-guiTests/...` | Swift Testing suites |
| `Resources/Info.plist` | Built-up `.app` bundle Info.plist |
| `Scripts/make-app.sh` | Assemble `.app` bundle from build artifacts |

---

## Task 1: Repo scaffolding (Package.swift, .gitignore, README/CLAUDE skeletons)

**Files:**
- Create: `.gitignore`
- Create: `Package.swift`
- Create: `README.md`
- Create: `CLAUDE.md`
- Create: `Sources/macSubtitleOCR-gui/App.swift` (placeholder so `swift build` parses)
- Create: `Tests/macSubtitleOCR-guiTests/SmokeTests.swift`

- [ ] **Step 1: Write `.gitignore`**

```
.build/
.swiftpm/
build/
*.xcodeproj
.DS_Store
Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macSubtitleOCR-gui",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "macSubtitleOCR-gui", targets: ["macSubtitleOCR-gui"]),
    ],
    targets: [
        .executableTarget(
            name: "macSubtitleOCR-gui",
            path: "Sources/macSubtitleOCR-gui",
            exclude: ["Resources/README.md"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "macSubtitleOCR-guiTests",
            dependencies: ["macSubtitleOCR-gui"],
            path: "Tests/macSubtitleOCR-guiTests"
        ),
    ]
)
```

- [ ] **Step 3: Create `Resources/` placeholder so SwiftPM finds the directory**

```bash
mkdir -p Sources/macSubtitleOCR-gui/Resources
cat > Sources/macSubtitleOCR-gui/Resources/README.md <<'EOF'
This directory holds the bundled macSubtitleOCR binary at build time.
The binary is gitignored and dropped here by `make build`.
EOF
```

- [ ] **Step 4: Write a placeholder `App.swift`**

```swift
import SwiftUI

@main
struct macSubtitleOCRGUIApp: App {
    var body: some Scene {
        WindowGroup {
            Text("macSubtitleOCR-gui — under construction")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
```

- [ ] **Step 5: Write `Tests/macSubtitleOCR-guiTests/SmokeTests.swift`**

```swift
import Testing
@testable import macSubtitleOCR_gui

@Test func packageBuilds() {
    #expect(Bool(true))
}
```

- [ ] **Step 6: Write `README.md` skeleton**

```markdown
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
```

- [ ] **Step 7: Write `CLAUDE.md` skeleton**

```markdown
# Claude instructions for macSubtitleOCR-gui

## Project shape

SwiftUI macOS app driven by SwiftPM. The upstream `macSubtitleOCR` CLI is vendored
as a git submodule under `Vendor/macSubtitleOCR` and built by the Makefile, which
drops the resulting binary into `Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR`
before invoking `swift build` on the GUI.

**Always use `make build` (or `make run` / `make app`), never `swift build` directly** —
otherwise the bundled binary will be missing.

## Tests

`swift test` runs Swift Testing suites in `Tests/macSubtitleOCR-guiTests/`. Pure
components (TrackProber, MKVToolNixExtractor, OCRRunner, SRTFinalizer) are TDD'd.
SwiftUI views are not snapshot-tested in v1.

## Updating upstream macSubtitleOCR

`make update` runs `git submodule update --remote` and rebuilds. Commit the bumped
submodule SHA after testing.

## Spec / plan

See `docs/superpowers/specs/2026-04-30-macSubtitleOCR-gui-design.md` and
`docs/superpowers/plans/2026-04-30-macSubtitleOCR-gui.md`.
```

- [ ] **Step 8: Verify the package builds**

Run: `swift build`
Expected: succeeds with a single warning-free build of the placeholder app.

- [ ] **Step 9: Verify tests run**

Run: `swift test`
Expected: 1 test passes.

- [ ] **Step 10: Commit**

```bash
git add .gitignore Package.swift README.md CLAUDE.md Sources Tests
git commit -m "Scaffold SwiftPM package and placeholder SwiftUI app"
```

---

## Task 2: Add macSubtitleOCR submodule + Makefile

**Files:**
- Create: `.gitmodules` (auto-created by `git submodule add`)
- Create: `Makefile`

- [ ] **Step 1: Add the submodule**

Run:
```bash
git submodule add https://github.com/ecdye/macSubtitleOCR.git Vendor/macSubtitleOCR
git submodule update --init --recursive
```
Expected: `Vendor/macSubtitleOCR/Package.swift` exists.

- [ ] **Step 2: Write `Makefile`**

```makefile
.PHONY: build run app update clean test

SWIFT       ?= swift
VENDOR      := Vendor/macSubtitleOCR
EMBEDDED    := Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR
APP_NAME    := macSubtitleOCR-gui
APP_BUNDLE  := build/$(APP_NAME).app

build: $(EMBEDDED)
	$(SWIFT) build -c release

$(EMBEDDED): $(VENDOR)/Package.swift
	@echo "==> Building upstream macSubtitleOCR"
	cd $(VENDOR) && $(SWIFT) build -c release
	@mkdir -p $(dir $(EMBEDDED))
	cp $(VENDOR)/.build/release/macSubtitleOCR $(EMBEDDED)
	@echo "==> Embedded binary at $(EMBEDDED)"

run: build
	$(SWIFT) run -c release $(APP_NAME)

test:
	$(SWIFT) test

update:
	@echo "==> Fetching latest macSubtitleOCR"
	git -C $(VENDOR) fetch origin
	git -C $(VENDOR) checkout origin/main
	@rm -f $(EMBEDDED)
	$(MAKE) build
	@echo "==> Submodule bumped. Review and commit:"
	@git status -- $(VENDOR)

app: build Scripts/make-app.sh
	bash Scripts/make-app.sh "$(APP_BUNDLE)"

clean:
	$(SWIFT) package clean
	rm -rf .build build
	rm -f $(EMBEDDED)
	-cd $(VENDOR) && $(SWIFT) package clean 2>/dev/null || true
```

- [ ] **Step 3: Verify upstream builds and binary lands in Resources**

Run: `make build`
Expected: ends with `==> Embedded binary at Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR`. The file exists and is executable.

- [ ] **Step 4: Verify the embedded binary works standalone**

Run: `Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR --help`
Expected: prints the usage banner from macSubtitleOCR.

- [ ] **Step 5: Commit**

```bash
git add .gitmodules Vendor/macSubtitleOCR Makefile
git commit -m "Vendor macSubtitleOCR as submodule and add Makefile"
```

---

## Task 3: `Track` model + `TrackProber` (TDD)

**Files:**
- Create: `Sources/macSubtitleOCR-gui/Probing/Track.swift`
- Create: `Sources/macSubtitleOCR-gui/Probing/TrackProber.swift`
- Create: `Tests/macSubtitleOCR-guiTests/TrackProberTests.swift`
- Create: `Tests/macSubtitleOCR-guiTests/Fixtures/mkvmerge-three-pgs.json`

- [ ] **Step 1: Write the `Track` value type**

```swift
// Sources/macSubtitleOCR-gui/Probing/Track.swift
import Foundation

public struct Track: Identifiable, Hashable, Sendable {
    public enum Codec: String, Sendable {
        case pgs       // S_HDMV/PGS
        case vobsub    // S_VOBSUB

        public var displayName: String {
            switch self {
            case .pgs: "PGS"
            case .vobsub: "VobSub"
            }
        }
    }

    public let id: Int            // mkvmerge track number (or 0 for synthetic)
    public let codec: Codec
    public let language: String?  // ISO 639-2 (e.g. "eng"), as returned by mkvmerge
    public let name: String?

    public init(id: Int, codec: Codec, language: String?, name: String?) {
        self.id = id
        self.codec = codec
        self.language = language
        self.name = name
    }
}
```

- [ ] **Step 2: Write the JSON fixture**

```json
{
  "tracks": [
    {"id": 0, "type": "video", "codec": "AVC/H.264/MPEG-4p10",
     "properties": {"language": "und"}},
    {"id": 1, "type": "audio", "codec": "DTS",
     "properties": {"language": "eng"}},
    {"id": 2, "type": "subtitles", "codec": "HDMV PGS",
     "properties": {"language": "eng", "track_name": "English"}},
    {"id": 3, "type": "subtitles", "codec": "HDMV PGS",
     "properties": {"language": "spa", "track_name": "Spanish"}},
    {"id": 4, "type": "subtitles", "codec": "VobSub",
     "properties": {"language": "fra"}}
  ]
}
```

Save to `Tests/macSubtitleOCR-guiTests/Fixtures/mkvmerge-three-pgs.json`.

- [ ] **Step 3: Write the failing tests**

```swift
// Tests/macSubtitleOCR-guiTests/TrackProberTests.swift
import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct TrackProberTests {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        else {
            // Fallback: read from the test source tree
            let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            return try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).json"))
        }
        return try Data(contentsOf: url)
    }

    @Test func parsesPGSAndVobSubFromMkvmergeJSON() throws {
        let data = try fixture("mkvmerge-three-pgs")
        let tracks = try TrackProber.parseMkvmergeJSON(data)
        #expect(tracks.count == 3)
        #expect(tracks[0].id == 2 && tracks[0].codec == .pgs && tracks[0].language == "eng")
        #expect(tracks[1].id == 3 && tracks[1].codec == .pgs && tracks[1].language == "spa")
        #expect(tracks[2].id == 4 && tracks[2].codec == .vobsub && tracks[2].language == "fra")
    }

    @Test func ignoresVideoAndAudioTracks() throws {
        let data = try fixture("mkvmerge-three-pgs")
        let tracks = try TrackProber.parseMkvmergeJSON(data)
        #expect(!tracks.contains { $0.id == 0 || $0.id == 1 })
    }

    @Test func emptyForFileWithNoSubs() throws {
        let json = #"{"tracks":[{"id":0,"type":"video","codec":"x","properties":{}}]}"#
        let tracks = try TrackProber.parseMkvmergeJSON(Data(json.utf8))
        #expect(tracks.isEmpty)
    }

    @Test func syntheticTrackForSupInput() {
        let url = URL(fileURLWithPath: "/tmp/movie.sup")
        let tracks = TrackProber.syntheticTracks(for: url)
        #expect(tracks.count == 1)
        #expect(tracks[0].codec == .pgs)
    }

    @Test func syntheticTrackForSubIdxInput() {
        let url = URL(fileURLWithPath: "/tmp/movie.idx")
        let tracks = TrackProber.syntheticTracks(for: url)
        #expect(tracks.count == 1)
        #expect(tracks[0].codec == .vobsub)
    }
}
```

- [ ] **Step 4: Run the tests; expect compile failure**

Run: `swift test`
Expected: fails because `TrackProber` doesn't exist yet.

- [ ] **Step 5: Implement `TrackProber`**

```swift
// Sources/macSubtitleOCR-gui/Probing/TrackProber.swift
import Foundation

public enum TrackProberError: Error, LocalizedError {
    case mkvmergeNotFound
    case mkvmergeFailed(stderr: String, code: Int32)
    case malformedJSON(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .mkvmergeNotFound:
            "mkvmerge not found. Install MKVToolNix: brew install mkvtoolnix"
        case .mkvmergeFailed(let stderr, let code):
            "mkvmerge exited with code \(code): \(stderr)"
        case .malformedJSON(let err):
            "Could not parse mkvmerge JSON: \(err.localizedDescription)"
        }
    }
}

public struct TrackProber {
    public let mkvmergePath: URL

    public init(mkvmergePath: URL) {
        self.mkvmergePath = mkvmergePath
    }

    /// Probe an input file and return its subtitle tracks (PGS/VobSub only).
    public func probe(_ input: URL) async throws -> [Track] {
        let ext = input.pathExtension.lowercased()
        if ext == "mkv" || ext == "mks" {
            let data = try await runMkvmerge(input)
            return try Self.parseMkvmergeJSON(data)
        }
        return Self.syntheticTracks(for: input)
    }

    /// Build a single synthetic track for non-container inputs (.sup, .sub, .idx).
    public static func syntheticTracks(for url: URL) -> [Track] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "sup":
            return [Track(id: 0, codec: .pgs, language: nil, name: nil)]
        case "sub", "idx":
            return [Track(id: 0, codec: .vobsub, language: nil, name: nil)]
        default:
            return []
        }
    }

    /// Parse `mkvmerge -J` output. Pure function, no I/O. PGS + VobSub only.
    public static func parseMkvmergeJSON(_ data: Data) throws -> [Track] {
        struct Root: Decodable { let tracks: [Entry] }
        struct Entry: Decodable {
            let id: Int
            let type: String
            let codec: String
            let properties: Properties?
        }
        struct Properties: Decodable {
            let language: String?
            let track_name: String?
        }

        do {
            let root = try JSONDecoder().decode(Root.self, from: data)
            return root.tracks.compactMap { entry in
                guard entry.type == "subtitles" else { return nil }
                let codec: Track.Codec
                switch entry.codec.lowercased() {
                case let s where s.contains("pgs"): codec = .pgs
                case let s where s.contains("vobsub") || s.contains("vob sub"): codec = .vobsub
                default: return nil
                }
                let lang = entry.properties?.language.flatMap { $0 == "und" ? nil : $0 }
                return Track(id: entry.id, codec: codec, language: lang, name: entry.properties?.track_name)
            }
        } catch {
            throw TrackProberError.malformedJSON(underlying: error)
        }
    }

    private func runMkvmerge(_ input: URL) async throws -> Data {
        let process = Process()
        process.executableURL = mkvmergePath
        process.arguments = ["-J", input.path]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw TrackProberError.mkvmergeNotFound
        }
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errStr = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TrackProberError.mkvmergeFailed(stderr: errStr, code: process.terminationStatus)
        }
        return outData
    }
}
```

- [ ] **Step 6: Make tests find the fixture**

Update `Package.swift` test target:

```swift
.testTarget(
    name: "macSubtitleOCR-guiTests",
    dependencies: ["macSubtitleOCR-gui"],
    path: "Tests/macSubtitleOCR-guiTests",
    resources: [.copy("Fixtures")]
),
```

- [ ] **Step 7: Run the tests; expect pass**

Run: `swift test`
Expected: 5 tests pass (1 smoke + 5 prober - 1 = correct count is 6 total).

- [ ] **Step 8: Commit**

```bash
git add Sources/macSubtitleOCR-gui/Probing Tests Package.swift
git commit -m "Add Track model and TrackProber with mkvmerge JSON parsing"
```

---

## Task 4: `ToolchainProbe`

**Files:**
- Create: `Sources/macSubtitleOCR-gui/Probing/ToolchainProbe.swift`
- Create: `Tests/macSubtitleOCR-guiTests/ToolchainProbeTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/macSubtitleOCR-guiTests/ToolchainProbeTests.swift
import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct ToolchainProbeTests {
    @Test func findsExistingExecutable() throws {
        let lsPath = ToolchainProbe.locate("ls", searchPaths: ["/bin", "/usr/bin"])
        #expect(lsPath?.path == "/bin/ls" || lsPath?.path == "/usr/bin/ls")
    }

    @Test func returnsNilForMissingExecutable() {
        let result = ToolchainProbe.locate("definitely-not-a-real-binary-xyz", searchPaths: ["/bin"])
        #expect(result == nil)
    }

    @Test func searchesPATHWhenProvided() throws {
        let result = ToolchainProbe.locate("ls", searchPaths: ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? [])
        #expect(result != nil)
    }
}
```

- [ ] **Step 2: Run tests; expect compile failure**

Run: `swift test`
Expected: `ToolchainProbe` undefined.

- [ ] **Step 3: Implement `ToolchainProbe`**

```swift
// Sources/macSubtitleOCR-gui/Probing/ToolchainProbe.swift
import Foundation

public enum ToolchainProbe {
    /// Default fallback paths for tools installed via Homebrew on Apple Silicon and Intel.
    public static let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Look up an executable by name in the given paths.
    public static func locate(_ name: String, searchPaths: [String]) -> URL? {
        let fm = FileManager.default
        for dir in searchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Locate a tool, checking $PATH and the Homebrew defaults.
    public static func locate(_ name: String) -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathDirs = path.split(separator: ":").map(String.init)
        return locate(name, searchPaths: pathDirs + homebrewPaths)
    }

    public struct MKVToolNix {
        public let mkvmerge: URL
        public let mkvextract: URL
    }

    /// Probe for both `mkvmerge` and `mkvextract`. Returns nil if either is missing.
    public static func mkvtoolnix() -> MKVToolNix? {
        guard let merge = locate("mkvmerge"), let extract = locate("mkvextract") else { return nil }
        return MKVToolNix(mkvmerge: merge, mkvextract: extract)
    }
}
```

- [ ] **Step 4: Run tests; expect pass**

Run: `swift test`
Expected: ToolchainProbeTests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/macSubtitleOCR-gui/Probing/ToolchainProbe.swift Tests/macSubtitleOCR-guiTests/ToolchainProbeTests.swift
git commit -m "Add ToolchainProbe for locating mkvtoolnix"
```

---

## Task 5: `TrackExtractor` protocol + `MKVToolNixExtractor` (TDD on argument construction)

**Files:**
- Create: `Sources/macSubtitleOCR-gui/Extraction/TrackExtractor.swift`
- Create: `Sources/macSubtitleOCR-gui/Extraction/MKVToolNixExtractor.swift`
- Create: `Tests/macSubtitleOCR-guiTests/MKVToolNixExtractorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/macSubtitleOCR-guiTests/MKVToolNixExtractorTests.swift
import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct MKVToolNixExtractorTests {
    @Test func buildsCorrectMkvextractArguments() {
        let input = URL(fileURLWithPath: "/Users/me/Movies/film.mkv")
        let output = URL(fileURLWithPath: "/tmp/track.sup")
        let args = MKVToolNixExtractor.arguments(input: input, trackID: 2, output: output)
        #expect(args == ["tracks", "/Users/me/Movies/film.mkv", "2:/tmp/track.sup"])
    }

    @Test func tempOutputURLEndsInSup() {
        let url = MKVToolNixExtractor.makeTempOutputURL(trackID: 3)
        #expect(url.pathExtension == "sup")
        #expect(url.lastPathComponent.contains("track-3"))
    }
}
```

- [ ] **Step 2: Run tests; expect compile failure**

Run: `swift test`
Expected: `MKVToolNixExtractor` undefined.

- [ ] **Step 3: Implement protocol + default extractor**

```swift
// Sources/macSubtitleOCR-gui/Extraction/TrackExtractor.swift
import Foundation

public protocol TrackExtractor: Sendable {
    /// Extract a single track from the given container into a standalone file.
    /// Returns the URL of the extracted file (caller is responsible for cleanup).
    func extract(input: URL, trackID: Int) async throws -> URL
}
```

```swift
// Sources/macSubtitleOCR-gui/Extraction/MKVToolNixExtractor.swift
import Foundation

public enum MKVToolNixExtractorError: Error, LocalizedError {
    case mkvextractFailed(stderr: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .mkvextractFailed(let s, let c): "mkvextract exited with code \(c): \(s)"
        }
    }
}

public struct MKVToolNixExtractor: TrackExtractor {
    public let mkvextractPath: URL

    public init(mkvextractPath: URL) {
        self.mkvextractPath = mkvextractPath
    }

    public func extract(input: URL, trackID: Int) async throws -> URL {
        let output = Self.makeTempOutputURL(trackID: trackID)
        let process = Process()
        process.executableURL = mkvextractPath
        process.arguments = Self.arguments(input: input, trackID: trackID, output: output)
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()  // discard

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errStr = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw MKVToolNixExtractorError.mkvextractFailed(stderr: errStr, code: process.terminationStatus)
        }
        return output
    }

    static func arguments(input: URL, trackID: Int, output: URL) -> [String] {
        ["tracks", input.path, "\(trackID):\(output.path)"]
    }

    static func makeTempOutputURL(trackID: Int) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macSubtitleOCR-gui", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("track-\(trackID).sup")
    }
}
```

- [ ] **Step 4: Run tests; expect pass**

Run: `swift test`
Expected: MKVToolNixExtractor tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/macSubtitleOCR-gui/Extraction Tests/macSubtitleOCR-guiTests/MKVToolNixExtractorTests.swift
git commit -m "Add TrackExtractor protocol and MKVToolNix implementation"
```

---

## Task 6: `BundledBinary`

**Files:**
- Create: `Sources/macSubtitleOCR-gui/OCR/BundledBinary.swift`
- Create: `Tests/macSubtitleOCR-guiTests/BundledBinaryTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/macSubtitleOCR-guiTests/BundledBinaryTests.swift
import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct BundledBinaryTests {
    @Test func devFallbackPathsIncludeVendorBuild() {
        let paths = BundledBinary.devFallbackPaths()
        #expect(paths.contains { $0.path.hasSuffix("Vendor/macSubtitleOCR/.build/release/macSubtitleOCR") })
    }

    @Test func returnsExecutableIfPresentAtAnyPath() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bundledbinary-test-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let fake = tmp.appendingPathComponent("macSubtitleOCR")
        FileManager.default.createFile(atPath: fake.path, contents: Data("#!/bin/sh\nexit 0\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolved = BundledBinary.firstExisting(in: [fake])
        #expect(resolved == fake)
    }

    @Test func returnsNilWhenNothingPresent() {
        let bogus = URL(fileURLWithPath: "/nonexistent/macSubtitleOCR-\(UUID())")
        #expect(BundledBinary.firstExisting(in: [bogus]) == nil)
    }
}
```

- [ ] **Step 2: Run tests; expect compile failure**

Run: `swift test`
Expected: `BundledBinary` undefined.

- [ ] **Step 3: Implement `BundledBinary`**

```swift
// Sources/macSubtitleOCR-gui/OCR/BundledBinary.swift
import Foundation

public enum BundledBinaryError: Error, LocalizedError {
    case notFound(searched: [URL])

    public var errorDescription: String? {
        switch self {
        case .notFound(let searched):
            "Could not find the macSubtitleOCR binary. Searched:\n" +
                searched.map { "  - \($0.path)" }.joined(separator: "\n") +
                "\n\nRun `make build` to compile and embed it."
        }
    }
}

public enum BundledBinary {
    /// Resolve the path to the embedded macSubtitleOCR binary, trying:
    ///   1. Bundle.main resources (assembled .app)
    ///   2. Bundle.module resources (swift run / swift test in this package)
    ///   3. Adjacent to the executable (post-build copy beside `swift run` output)
    ///   4. Vendored submodule build artifact (developer fallback)
    public static func resolve() throws -> URL {
        let candidates = bundledPaths() + devFallbackPaths()
        if let url = firstExisting(in: candidates) { return url }
        throw BundledBinaryError.notFound(searched: candidates)
    }

    static func bundledPaths() -> [URL] {
        var paths: [URL] = []
        if let main = Bundle.main.url(forResource: "macSubtitleOCR", withExtension: nil) {
            paths.append(main)
        }
        if let module = Bundle.module.url(forResource: "macSubtitleOCR", withExtension: nil) {
            paths.append(module)
        }
        // Adjacent to the running executable (Contents/MacOS/...)
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            paths.append(exe.appendingPathComponent("macSubtitleOCR"))
        }
        return paths
    }

    static func devFallbackPaths() -> [URL] {
        // Walk up from this source file to find Vendor/macSubtitleOCR/.build/release/macSubtitleOCR
        let here = URL(fileURLWithPath: #filePath)
        var dir = here
        for _ in 0..<8 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir
                .appendingPathComponent("Vendor/macSubtitleOCR/.build/release/macSubtitleOCR")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return [candidate]
            }
        }
        // Even if not present, return the path so error messages show what we tried
        let projectRoot = here
            .deletingLastPathComponent()  // OCR
            .deletingLastPathComponent()  // macSubtitleOCR-gui
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // repo root
        return [projectRoot.appendingPathComponent("Vendor/macSubtitleOCR/.build/release/macSubtitleOCR")]
    }

    static func firstExisting(in candidates: [URL]) -> URL? {
        let fm = FileManager.default
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }
}
```

- [ ] **Step 4: Run tests; expect pass**

Run: `swift test`
Expected: BundledBinary tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/macSubtitleOCR-gui/OCR/BundledBinary.swift Tests/macSubtitleOCR-guiTests/BundledBinaryTests.swift
git commit -m "Add BundledBinary helper to locate macSubtitleOCR at runtime"
```

---

## Task 7: `OCRRunner` (TDD on argument construction; integration kept light)

**Files:**
- Create: `Sources/macSubtitleOCR-gui/OCR/OCRRunner.swift`
- Create: `Tests/macSubtitleOCR-guiTests/OCRRunnerTests.swift`

- [ ] **Step 1: Write failing tests for argument construction and progress parsing**

```swift
// Tests/macSubtitleOCR-guiTests/OCRRunnerTests.swift
import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct OCRRunnerTests {
    @Test func basicArguments() {
        let opts = OCRRunner.Options(languages: "en", invert: false, customWords: nil, disableICorrection: false)
        let args = OCRRunner.arguments(input: URL(fileURLWithPath: "/tmp/x.sup"),
                                       outputDir: URL(fileURLWithPath: "/tmp/out"),
                                       options: opts)
        #expect(args == ["/tmp/x.sup", "/tmp/out", "--languages", "en"])
    }

    @Test func argumentsWithFlags() {
        let opts = OCRRunner.Options(languages: "en,es", invert: true, customWords: "Tatooine,Yavin",
                                     disableICorrection: true)
        let args = OCRRunner.arguments(input: URL(fileURLWithPath: "/tmp/x.sup"),
                                       outputDir: URL(fileURLWithPath: "/tmp/out"),
                                       options: opts)
        #expect(args.contains("--languages"))
        #expect(args.contains("en,es"))
        #expect(args.contains("--invert"))
        #expect(args.contains("--custom-words"))
        #expect(args.contains("Tatooine,Yavin"))
        #expect(args.contains("--disable-i-correction"))
    }
}
```

- [ ] **Step 2: Run tests; expect compile failure**

Run: `swift test`

- [ ] **Step 3: Implement `OCRRunner`**

```swift
// Sources/macSubtitleOCR-gui/OCR/OCRRunner.swift
import Foundation

public actor OCRRunner {
    public struct Options: Sendable, Equatable {
        public var languages: String           // ISO 639-1, comma separated; default "en"
        public var invert: Bool
        public var customWords: String?
        public var disableICorrection: Bool

        public init(languages: String = "en",
                    invert: Bool = false,
                    customWords: String? = nil,
                    disableICorrection: Bool = false) {
            self.languages = languages
            self.invert = invert
            self.customWords = customWords
            self.disableICorrection = disableICorrection
        }
    }

    public struct Output: Sendable {
        public let outputDir: URL
        public let logLines: [String]
    }

    public enum Event: Sendable {
        case logLine(String)
        case finished(Output)
        case failed(stderr: String, code: Int32)
    }

    public let binary: URL
    public init(binary: URL) {
        self.binary = binary
    }

    public func run(input: URL, options: Options) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let outputDir = Self.makeOutputDir()
            let process = Process()
            process.executableURL = binary
            process.arguments = Self.arguments(input: input, outputDir: outputDir, options: options)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var logLines: [String] = []
            let stderrHandle = stderrPipe.fileHandleForReading
            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                let trimmed = line.split(separator: "\n").map(String.init)
                for l in trimmed {
                    logLines.append(l)
                    continuation.yield(.logLine(l))
                }
            }

            process.terminationHandler = { p in
                stderrHandle.readabilityHandler = nil
                if p.terminationStatus == 0 {
                    continuation.yield(.finished(Output(outputDir: outputDir, logLines: logLines)))
                } else {
                    let stderrStr = logLines.joined(separator: "\n")
                    continuation.yield(.failed(stderr: stderrStr, code: p.terminationStatus))
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.yield(.failed(stderr: "\(error.localizedDescription)", code: -1))
                continuation.finish()
            }
        }
    }

    static func arguments(input: URL, outputDir: URL, options: Options) -> [String] {
        var args = [input.path, outputDir.path, "--languages", options.languages]
        if options.invert { args.append("--invert") }
        if let words = options.customWords, !words.isEmpty {
            args.append(contentsOf: ["--custom-words", words])
        }
        if options.disableICorrection { args.append("--disable-i-correction") }
        return args
    }

    static func makeOutputDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macSubtitleOCR-gui", isDirectory: true)
            .appendingPathComponent("out-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

- [ ] **Step 4: Run tests; expect pass**

Run: `swift test`
Expected: OCRRunner argument tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/macSubtitleOCR-gui/OCR/OCRRunner.swift Tests/macSubtitleOCR-guiTests/OCRRunnerTests.swift
git commit -m "Add OCRRunner actor with streaming events and argument construction"
```

---

## Task 8: `SRTFinalizer` (TDD on filename rules)

**Files:**
- Create: `Sources/macSubtitleOCR-gui/Finalize/SRTFinalizer.swift`
- Create: `Tests/macSubtitleOCR-guiTests/SRTFinalizerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/macSubtitleOCR-guiTests/SRTFinalizerTests.swift
import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct SRTFinalizerTests {
    @Test func basicFilenameForMKV() {
        let input = URL(fileURLWithPath: "/Users/me/Movies/Film.mkv")
        let url = SRTFinalizer.targetURL(forInput: input, language: "en", existingFiles: [])
        #expect(url.path == "/Users/me/Movies/Film.en.srt")
    }

    @Test func usesGivenLanguageCode() {
        let input = URL(fileURLWithPath: "/x/Movie.mkv")
        let url = SRTFinalizer.targetURL(forInput: input, language: "spa", existingFiles: [])
        #expect(url.lastPathComponent == "Movie.spa.srt")
    }

    @Test func conflictGetsSuffix() {
        let input = URL(fileURLWithPath: "/x/Movie.mkv")
        let existing: Set<URL> = [
            URL(fileURLWithPath: "/x/Movie.en.srt"),
            URL(fileURLWithPath: "/x/Movie.en-1.srt"),
        ]
        let url = SRTFinalizer.targetURL(forInput: input, language: "en", existingFiles: existing)
        #expect(url.lastPathComponent == "Movie.en-2.srt")
    }

    @Test func handlesSupInput() {
        let input = URL(fileURLWithPath: "/x/Bonus.sup")
        let url = SRTFinalizer.targetURL(forInput: input, language: "en", existingFiles: [])
        #expect(url.lastPathComponent == "Bonus.en.srt")
    }

    @Test func nilLanguageOmitsCode() {
        let input = URL(fileURLWithPath: "/x/Movie.mkv")
        let url = SRTFinalizer.targetURL(forInput: input, language: nil, existingFiles: [])
        #expect(url.lastPathComponent == "Movie.srt")
    }

    @Test func movesProducedSRTToTarget() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("srtfin-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let producedDir = tmp.appendingPathComponent("ocr-out")
        try FileManager.default.createDirectory(at: producedDir, withIntermediateDirectories: true)
        let producedSRT = producedDir.appendingPathComponent("track_2.srt")
        try Data("1\n00:00:01,000 --> 00:00:02,000\nHello\n".utf8).write(to: producedSRT)

        let inputVideo = tmp.appendingPathComponent("Film.mkv")
        try Data().write(to: inputVideo)

        let final = try SRTFinalizer.finalize(producedSRTDir: producedDir,
                                              inputURL: inputVideo,
                                              language: "en")
        #expect(FileManager.default.fileExists(atPath: final.path))
        #expect(final.lastPathComponent == "Film.en.srt")
    }
}
```

- [ ] **Step 2: Run tests; expect compile failure**

Run: `swift test`

- [ ] **Step 3: Implement `SRTFinalizer`**

```swift
// Sources/macSubtitleOCR-gui/Finalize/SRTFinalizer.swift
import Foundation

public enum SRTFinalizerError: Error, LocalizedError {
    case noSRTProduced(searched: URL)
    case multipleSRTs(producedDir: URL, count: Int)

    public var errorDescription: String? {
        switch self {
        case .noSRTProduced(let dir):
            "macSubtitleOCR did not produce a .srt file in \(dir.path). The track may be empty or unsupported."
        case .multipleSRTs(let dir, let n):
            "macSubtitleOCR produced \(n) .srt files in \(dir.path) — expected exactly one. " +
                "(This usually means a single-track extraction wasn't really single-track.)"
        }
    }
}

public enum SRTFinalizer {
    /// Compute the destination URL for the SRT, avoiding collisions.
    public static func targetURL(forInput input: URL, language: String?, existingFiles: Set<URL>) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let suffix = language.flatMap { $0.isEmpty ? nil : ".\($0)" } ?? ""

        let primary = dir.appendingPathComponent("\(base)\(suffix).srt")
        if !existingFiles.contains(primary) { return primary }

        for n in 1... {
            let candidate = dir.appendingPathComponent("\(base)\(suffix)-\(n).srt")
            if !existingFiles.contains(candidate) { return candidate }
        }
        return primary  // unreachable
    }

    /// Move the produced SRT next to `inputURL`. Returns the final URL.
    public static func finalize(producedSRTDir: URL, inputURL: URL, language: String?) throws -> URL {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: producedSRTDir,
                                                  includingPropertiesForKeys: nil)
        let srts = contents.filter { $0.pathExtension.lowercased() == "srt" }

        guard let produced = srts.first else {
            throw SRTFinalizerError.noSRTProduced(searched: producedSRTDir)
        }
        if srts.count > 1 {
            throw SRTFinalizerError.multipleSRTs(producedDir: producedSRTDir, count: srts.count)
        }

        let dir = inputURL.deletingLastPathComponent()
        let existing = Set(((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []))
        let target = targetURL(forInput: inputURL, language: language, existingFiles: existing)

        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        try fm.moveItem(at: produced, to: target)
        return target
    }
}
```

- [ ] **Step 4: Run tests; expect pass**

Run: `swift test`

- [ ] **Step 5: Commit**

```bash
git add Sources/macSubtitleOCR-gui/Finalize Tests/macSubtitleOCR-guiTests/SRTFinalizerTests.swift
git commit -m "Add SRTFinalizer with conflict-aware filename resolution"
```

---

## Task 9: `SubtitleJob` state container

**Files:**
- Create: `Sources/macSubtitleOCR-gui/SubtitleJob.swift`
- Create: `Tests/macSubtitleOCR-guiTests/SubtitleJobTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/macSubtitleOCR-guiTests/SubtitleJobTests.swift
import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct SubtitleJobTests {
    @Test func startsInIdlePhase() {
        let job = SubtitleJob()
        if case .idle = job.phase { } else { Issue.record("expected .idle"); return }
    }

    @Test func transitionsToTracksAfterProbing() {
        let job = SubtitleJob()
        job.input = URL(fileURLWithPath: "/tmp/x.sup")
        job.tracks = [Track(id: 0, codec: .pgs, language: nil, name: nil)]
        job.advanceToTracks()
        if case .tracks = job.phase { } else { Issue.record("expected .tracks") }
    }

    @Test func resetClearsState() {
        let job = SubtitleJob()
        job.input = URL(fileURLWithPath: "/tmp/x.sup")
        job.advanceToTracks()
        job.reset()
        #expect(job.input == nil)
        #expect(job.tracks.isEmpty)
        if case .idle = job.phase { } else { Issue.record("expected .idle") }
    }
}
```

- [ ] **Step 2: Run tests; expect compile failure**

Run: `swift test`

- [ ] **Step 3: Implement `SubtitleJob`**

```swift
// Sources/macSubtitleOCR-gui/SubtitleJob.swift
import Foundation
import Observation

@MainActor
@Observable
public final class SubtitleJob {
    public enum Phase: Equatable {
        case idle
        case probing
        case tracks
        case running(stage: Stage)
        case done(output: URL)
        case failed(message: String)

        public enum Stage: Equatable {
            case extracting
            case ocr
            case finalizing
        }
    }

    public var input: URL?
    public var tracks: [Track] = []
    public var selectedTrack: Track?
    public var options: OCRRunner.Options = .init()
    public var phase: Phase = .idle
    public var logLines: [String] = []
    public var error: Error?

    public init() {}

    public func advanceToTracks() {
        phase = .tracks
    }

    public func reset() {
        input = nil
        tracks = []
        selectedTrack = nil
        options = .init()
        phase = .idle
        logLines = []
        error = nil
    }

    public func appendLog(_ line: String) {
        logLines.append(line)
    }
}
```

- [ ] **Step 4: Run tests; expect pass**

Run: `swift test`

- [ ] **Step 5: Commit**

```bash
git add Sources/macSubtitleOCR-gui/SubtitleJob.swift Tests/macSubtitleOCR-guiTests/SubtitleJobTests.swift
git commit -m "Add SubtitleJob observable state container"
```

---

## Task 10: `App.swift` + `AppView.swift` (phase router)

**Files:**
- Modify: `Sources/macSubtitleOCR-gui/App.swift`
- Create: `Sources/macSubtitleOCR-gui/AppView.swift`

- [ ] **Step 1: Replace placeholder `App.swift`**

```swift
// Sources/macSubtitleOCR-gui/App.swift
import SwiftUI

@main
struct macSubtitleOCRGUIApp: App {
    @State private var job = SubtitleJob()

    var body: some Scene {
        WindowGroup("macSubtitleOCR") {
            AppView()
                .environment(job)
                .frame(minWidth: 560, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 2: Write `AppView.swift` (router stub)**

```swift
// Sources/macSubtitleOCR-gui/AppView.swift
import SwiftUI

struct AppView: View {
    @Environment(SubtitleJob.self) private var job

    var body: some View {
        Group {
            switch job.phase {
            case .idle, .probing:
                DropView()
            case .tracks:
                TracksView()
            case .running:
                RunView()
            case .done, .failed:
                DoneView()
            }
        }
        .padding(20)
    }
}
```

- [ ] **Step 3: Add temporary stub views so the project compiles**

```swift
// Add to bottom of AppView.swift, will be replaced in later tasks:
struct DropView: View { var body: some View { Text("Drop") } }
struct TracksView: View { var body: some View { Text("Tracks") } }
struct RunView: View { var body: some View { Text("Run") } }
struct DoneView: View { var body: some View { Text("Done") } }
```

- [ ] **Step 4: Verify it builds**

Run: `make build`
Expected: succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/macSubtitleOCR-gui/App.swift Sources/macSubtitleOCR-gui/AppView.swift
git commit -m "Add App entrypoint and AppView phase router"
```

---

## Task 11: `DropView`

**Files:**
- Create: `Sources/macSubtitleOCR-gui/Views/DropView.swift`
- Modify: `Sources/macSubtitleOCR-gui/AppView.swift` (remove DropView stub)

- [ ] **Step 1: Implement `DropView` with drag-and-drop + file picker + toolchain check**

```swift
// Sources/macSubtitleOCR-gui/Views/DropView.swift
import SwiftUI
import UniformTypeIdentifiers

struct DropView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var isTargeted = false
    @State private var toolchain: ToolchainProbe.MKVToolNix? = ToolchainProbe.mkvtoolnix()

    private static let acceptedExtensions: Set<String> = ["mkv", "mks", "sup", "sub", "idx"]

    var body: some View {
        VStack(spacing: 18) {
            if toolchain == nil {
                missingToolchainBanner
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Drop a .mkv, .sup, .sub, or .idx file")
                        .font(.headline)
                    Text("or")
                        .foregroundStyle(.secondary)
                    Button("Choose file…") { openFilePicker() }
                        .keyboardShortcut("o")
                }
                .padding(40)
            }
            .frame(minHeight: 240)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
                return true
            }
            .opacity(toolchain == nil ? 0.5 : 1.0)
            .disabled(toolchain == nil)
        }
    }

    private var missingToolchainBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("MKVToolNix is required").font(.headline)
                Text("Install it with Homebrew, then click \u{201C}I installed it\u{201D}.")
                    .foregroundStyle(.secondary)
                HStack {
                    Text("brew install mkvtoolnix")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install mkvtoolnix", forType: .string)
                    }
                    Spacer()
                    Button("I installed it") {
                        toolchain = ToolchainProbe.mkvtoolnix()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.allowedTypes()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { accept(url) }
    }

    private static func allowedTypes() -> [UTType] {
        ["mkv", "mks", "sup", "sub", "idx"].compactMap { UTType(filenameExtension: $0) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { accept(url) }
        }
    }

    private func accept(_ url: URL) {
        guard Self.acceptedExtensions.contains(url.pathExtension.lowercased()) else {
            job.phase = .failed(message: "Unsupported file type: .\(url.pathExtension)")
            return
        }
        Task { await probe(url) }
    }

    private func probe(_ url: URL) async {
        job.input = url
        job.phase = .probing
        guard let mkvtoolnix = toolchain else { return }
        do {
            let prober = TrackProber(mkvmergePath: mkvtoolnix.mkvmerge)
            let tracks = try await prober.probe(url)
            await MainActor.run {
                job.tracks = tracks
                if tracks.isEmpty {
                    job.phase = .failed(message: "No PGS or VobSub tracks found in this file.")
                } else if tracks.count == 1 {
                    job.selectedTrack = tracks[0]
                    job.advanceToTracks()  // still show the track screen so user can set language
                } else {
                    job.advanceToTracks()
                }
            }
        } catch {
            await MainActor.run {
                job.phase = .failed(message: error.localizedDescription)
            }
        }
    }
}
```

- [ ] **Step 2: Remove the `DropView` stub from `AppView.swift`**

In `AppView.swift`, delete just this line:
```swift
struct DropView: View { var body: some View { Text("Drop") } }
```

- [ ] **Step 3: Verify build + run**

Run: `make run`
Expected: app launches, shows drop zone. If mkvtoolnix isn't installed, banner appears. Drop a file (don't process yet — TracksView is still a stub).

- [ ] **Step 4: Commit**

```bash
git add Sources/macSubtitleOCR-gui/Views/DropView.swift Sources/macSubtitleOCR-gui/AppView.swift
git commit -m "Add DropView with drag-drop, file picker, and toolchain check"
```

---

## Task 12: `TracksView`

**Files:**
- Create: `Sources/macSubtitleOCR-gui/Views/TracksView.swift`
- Modify: `Sources/macSubtitleOCR-gui/AppView.swift` (remove TracksView stub)

- [ ] **Step 1: Implement `TracksView`**

```swift
// Sources/macSubtitleOCR-gui/Views/TracksView.swift
import SwiftUI

struct TracksView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var showAdvanced = false

    var body: some View {
        @Bindable var job = job

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Choose a subtitle track").font(.title2).bold()
                    if let url = job.input {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                Button("Cancel") { job.reset() }
            }

            if job.tracks.count > 1 {
                List(selection: $job.selectedTrack) {
                    ForEach(job.tracks) { track in
                        TrackRow(track: track)
                            .tag(Optional(track))
                    }
                }
                .frame(minHeight: 160)
            } else if let only = job.tracks.first {
                TrackRow(track: only)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .onAppear { job.selectedTrack = only }
            }

            DisclosureGroup("OCR options", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Languages")
                        TextField("en", text: $job.options.languages)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Text("ISO 639-1, comma-separated").foregroundStyle(.secondary).font(.caption)
                    }
                    Toggle("Invert images before OCR", isOn: $job.options.invert)
                    Toggle("Disable l→I correction", isOn: $job.options.disableICorrection)
                    HStack {
                        Text("Custom words")
                        TextField("optional", text: Binding(
                            get: { job.options.customWords ?? "" },
                            set: { job.options.customWords = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 6)
            }

            HStack {
                Spacer()
                Button("Run OCR") { startRun() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(job.selectedTrack == nil)
            }
        }
    }

    private func startRun() {
        Task { await OCRPipeline.run(job: job) }
    }
}

private struct TrackRow: View {
    let track: Track
    var body: some View {
        HStack {
            Image(systemName: "captions.bubble")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text("Track \(track.id) — \(track.codec.displayName)")
                    .font(.body)
                if let name = track.name, !name.isEmpty {
                    Text(name).foregroundStyle(.secondary).font(.caption)
                }
            }
            Spacer()
            if let lang = track.language {
                Text(lang.uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }
}
```

- [ ] **Step 2: Stub `OCRPipeline` (will be filled in Task 14)**

Create `Sources/macSubtitleOCR-gui/OCR/OCRPipeline.swift`:

```swift
// Sources/macSubtitleOCR-gui/OCR/OCRPipeline.swift
import Foundation

@MainActor
enum OCRPipeline {
    static func run(job: SubtitleJob) async {
        // Filled in Task 14
        job.phase = .running(stage: .extracting)
    }
}
```

- [ ] **Step 3: Remove the `TracksView` stub from `AppView.swift`**

Delete just this line in `AppView.swift`:
```swift
struct TracksView: View { var body: some View { Text("Tracks") } }
```

- [ ] **Step 4: Verify build**

Run: `make build`
Expected: succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/macSubtitleOCR-gui/Views/TracksView.swift Sources/macSubtitleOCR-gui/OCR/OCRPipeline.swift Sources/macSubtitleOCR-gui/AppView.swift
git commit -m "Add TracksView with selection list and OCR options"
```

---

## Task 13: `RunView` and `DoneView`

**Files:**
- Create: `Sources/macSubtitleOCR-gui/Views/RunView.swift`
- Create: `Sources/macSubtitleOCR-gui/Views/DoneView.swift`
- Modify: `Sources/macSubtitleOCR-gui/AppView.swift` (remove stubs)

- [ ] **Step 1: Implement `RunView`**

```swift
// Sources/macSubtitleOCR-gui/Views/RunView.swift
import SwiftUI

struct RunView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(stageLabel).font(.title3)
                Spacer()
            }

            if let url = job.input {
                Text(url.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            ProgressView().progressViewStyle(.linear)

            DisclosureGroup("Log", isExpanded: $showLog) {
                ScrollView {
                    Text(job.logLines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(minHeight: 160, maxHeight: 240)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("Cancel", role: .destructive) { job.reset() }
            }
        }
    }

    private var stageLabel: String {
        if case .running(let stage) = job.phase {
            switch stage {
            case .extracting: return "Extracting subtitle track…"
            case .ocr: return "Running OCR…"
            case .finalizing: return "Saving SRT…"
            }
        }
        return "Working…"
    }
}
```

- [ ] **Step 2: Implement `DoneView`**

```swift
// Sources/macSubtitleOCR-gui/Views/DoneView.swift
import SwiftUI
import AppKit

struct DoneView: View {
    @Environment(SubtitleJob.self) private var job

    var body: some View {
        VStack(spacing: 18) {
            switch job.phase {
            case .done(let output):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Saved").font(.title2).bold()
                Text(output.lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                    Button("OCR another") { job.reset() }
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let msg):
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Failed").font(.title2).bold()
                Text(msg)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if !job.logLines.isEmpty {
                    DisclosureGroup("Details") {
                        ScrollView {
                            Text(job.logLines.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(minHeight: 120, maxHeight: 200)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                HStack {
                    Button("Try again") { job.reset() }
                        .keyboardShortcut(.defaultAction)
                }
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Remove the `RunView` and `DoneView` stubs from `AppView.swift`**

Delete these two lines:
```swift
struct RunView: View { var body: some View { Text("Run") } }
struct DoneView: View { var body: some View { Text("Done") } }
```

- [ ] **Step 4: Verify build**

Run: `make build`

- [ ] **Step 5: Commit**

```bash
git add Sources/macSubtitleOCR-gui/Views Sources/macSubtitleOCR-gui/AppView.swift
git commit -m "Add RunView and DoneView for progress and final states"
```

---

## Task 14: `OCRPipeline` — wire extraction → OCR → finalize

**Files:**
- Modify: `Sources/macSubtitleOCR-gui/OCR/OCRPipeline.swift`

- [ ] **Step 1: Replace the stub with the full pipeline**

```swift
// Sources/macSubtitleOCR-gui/OCR/OCRPipeline.swift
import Foundation

@MainActor
enum OCRPipeline {
    static func run(job: SubtitleJob) async {
        guard let input = job.input,
              let track = job.selectedTrack,
              let toolchain = ToolchainProbe.mkvtoolnix() else {
            job.phase = .failed(message: "Internal error: missing input, track, or toolchain.")
            return
        }

        let binary: URL
        do {
            binary = try BundledBinary.resolve()
        } catch {
            job.phase = .failed(message: error.localizedDescription)
            return
        }

        // Stage 1: Extract (only for MKV; .sup/.sub passes through)
        var ocrInput = input
        if input.pathExtension.lowercased() == "mkv" || input.pathExtension.lowercased() == "mks" {
            job.phase = .running(stage: .extracting)
            do {
                let extractor = MKVToolNixExtractor(mkvextractPath: toolchain.mkvextract)
                ocrInput = try await extractor.extract(input: input, trackID: track.id)
            } catch {
                job.phase = .failed(message: error.localizedDescription)
                return
            }
        }

        // Stage 2: OCR
        job.phase = .running(stage: .ocr)
        let runner = OCRRunner(binary: binary)
        let stream = await runner.run(input: ocrInput, options: job.options)

        var producedDir: URL?
        for await event in stream {
            switch event {
            case .logLine(let line):
                job.appendLog(line)
            case .finished(let out):
                producedDir = out.outputDir
            case .failed(let stderr, let code):
                job.appendLog(stderr)
                job.phase = .failed(message: "macSubtitleOCR exited with code \(code).")
                return
            }
        }

        guard let dir = producedDir else {
            job.phase = .failed(message: "macSubtitleOCR produced no output.")
            return
        }

        // Stage 3: Finalize
        job.phase = .running(stage: .finalizing)
        do {
            let finalURL = try SRTFinalizer.finalize(
                producedSRTDir: dir,
                inputURL: input,
                language: track.language ?? job.options.languages.split(separator: ",").first.map(String.init)
            )
            // Clean up the temp extraction file if we made one
            if ocrInput != input { try? FileManager.default.removeItem(at: ocrInput) }
            try? FileManager.default.removeItem(at: dir)
            job.phase = .done(output: finalURL)
        } catch {
            job.phase = .failed(message: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `make build`

- [ ] **Step 3: Manual smoke test with a real MKV that has PGS subs**

Run: `make run`
Drop an MKV with PGS into the window. Pick a track. Run OCR. Verify a `.<lang>.srt` appears next to the input.

- [ ] **Step 4: Commit**

```bash
git add Sources/macSubtitleOCR-gui/OCR/OCRPipeline.swift
git commit -m "Wire OCRPipeline: extraction → OCR → finalization"
```

---

## Task 15: `make app` — assemble a real `.app` bundle

**Files:**
- Create: `Scripts/make-app.sh`
- Create: `Resources/Info.plist`

- [ ] **Step 1: Write `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>macSubtitleOCR-gui</string>
  <key>CFBundleDisplayName</key>
  <string>macSubtitleOCR</string>
  <key>CFBundleIdentifier</key>
  <string>com.jeffalldridge.macSubtitleOCR-gui</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleExecutable</key>
  <string>macSubtitleOCR-gui</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Subtitle file</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.movie</string>
        <string>public.data</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
```

- [ ] **Step 2: Write `Scripts/make-app.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: make-app.sh <path/to/MyApp.app>}"
EXEC_NAME="macSubtitleOCR-gui"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp ".build/release/${EXEC_NAME}" "$APP/Contents/MacOS/${EXEC_NAME}"
cp "Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR" "$APP/Contents/Resources/macSubtitleOCR"
chmod +x "$APP/Contents/Resources/macSubtitleOCR"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Built $APP"
```

- [ ] **Step 3: Make the script executable and run it**

Run:
```bash
chmod +x Scripts/make-app.sh
make app
ls -la build/macSubtitleOCR-gui.app/Contents/Resources/
open build/macSubtitleOCR-gui.app
```
Expected: `.app` opens, the GUI works, finds its embedded macSubtitleOCR (`Bundle.main` lookup hits first).

- [ ] **Step 4: Commit**

```bash
git add Resources/Info.plist Scripts/make-app.sh
git commit -m "Add make app target that assembles a .app bundle"
```

---

## Task 16: Polish README and CLAUDE.md

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Replace `README.md`**

```markdown
# macSubtitleOCR-gui

A polished macOS SwiftUI front-end for [macSubtitleOCR](https://github.com/ecdye/macSubtitleOCR).
Drop a `.mkv`, `.sup`, `.sub`, or `.idx` file, pick a single PGS or VobSub track,
and get a clean `.srt` next to your source file. Designed for muxing into MP4
soft-subs with [Subler](https://subler.org).

## Why

`macSubtitleOCR` is the best macOS-native PGS-to-SRT tool there is, but its CLI OCRs
*every* subtitle track in an MKV, which is rarely what you want when you're cutting
a single language for a release. This GUI lets you pick exactly one track, runs the
OCR with progress, and writes the SRT next to your source with a clean filename.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain (Xcode 16+ command-line tools, or [Swift.org toolchain](https://swift.org/download/))
- [MKVToolNix](https://mkvtoolnix.download): `brew install mkvtoolnix`

## Build & run

```sh
make build      # compiles the vendored macSubtitleOCR + this app
make run        # builds and runs straight from the terminal
make app        # assembles build/macSubtitleOCR-gui.app you can drag to /Applications
make test       # runs the Swift Testing suites
make clean      # wipes build artifacts
```

The first build is slow (it compiles `macSubtitleOCR` from source). Subsequent
builds reuse the cache.

## Update upstream macSubtitleOCR

```sh
make update     # bumps the submodule to upstream/main and rebuilds
```

After verifying the new build works, commit the bumped submodule SHA:

```sh
git add Vendor/macSubtitleOCR
git commit -m "Bump macSubtitleOCR to <upstream-sha>"
```

## Workflow

1. Drop a video / subtitle file into the window.
2. If it's an MKV with multiple subtitle tracks, pick the one you want.
3. (Optional) tweak language code, invert, custom words.
4. Click **Run OCR**. Watch progress, see the tool's log if you want.
5. Get a `MovieName.<lang>.srt` next to your source. Done.

## Architecture (one-liner per piece)

- **`TrackProber`** — runs `mkvmerge -J` and parses subtitle tracks
- **`MKVToolNixExtractor`** — extracts a single track to a temp `.sup` via `mkvextract`
- **`OCRRunner`** — invokes the bundled `macSubtitleOCR` binary, streams progress
- **`SRTFinalizer`** — names and moves the resulting SRT next to the input
- **`SubtitleJob`** — observable state container driving the four-phase UI

See [docs/superpowers/specs/](docs/superpowers/specs/) for the design rationale
and [docs/superpowers/plans/](docs/superpowers/plans/) for the implementation plan.

## License

Same license as upstream macSubtitleOCR (MIT).
```

- [ ] **Step 2: Replace `CLAUDE.md`**

```markdown
# Claude instructions for macSubtitleOCR-gui

## What this project is

A SwiftUI macOS app that wraps the upstream `macSubtitleOCR` CLI. The upstream tool
is vendored as a git submodule at `Vendor/macSubtitleOCR/`. The Makefile builds it
and copies the resulting binary into `Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR`
before invoking `swift build` on the GUI.

## Build hygiene

- **Always use `make build` / `make run` / `make app`.** Never run `swift build`
  directly without first running `make build` — the binary at
  `Sources/macSubtitleOCR-gui/Resources/macSubtitleOCR` is gitignored and won't
  exist on a fresh clone until the Makefile produces it.
- The first `make build` is slow because it compiles `macSubtitleOCR` from source.
- `make clean` wipes everything, including the embedded binary.

## Tests

`swift test` runs Swift Testing (`import Testing`) suites in
`Tests/macSubtitleOCR-guiTests/`. Pure components (TrackProber, MKVToolNixExtractor,
OCRRunner, SRTFinalizer, SubtitleJob, BundledBinary, ToolchainProbe) are TDD'd with
real assertions. SwiftUI views are not snapshot-tested in v1.

## Updating upstream macSubtitleOCR

`make update` runs `git submodule update --remote` and rebuilds. After verifying
the new build works, commit the bumped submodule SHA. Don't bump it without testing
because upstream may change its CLI surface.

## Project layout reminder

- `Sources/macSubtitleOCR-gui/Probing/` — TrackProber, ToolchainProbe, Track model
- `Sources/macSubtitleOCR-gui/Extraction/` — TrackExtractor protocol + mkvextract impl
- `Sources/macSubtitleOCR-gui/OCR/` — OCRRunner, OCRPipeline, BundledBinary
- `Sources/macSubtitleOCR-gui/Finalize/` — SRTFinalizer
- `Sources/macSubtitleOCR-gui/Views/` — DropView, TracksView, RunView, DoneView
- `Sources/macSubtitleOCR-gui/SubtitleJob.swift` — single source of truth

## Spec / plan

See `docs/superpowers/specs/2026-04-30-macSubtitleOCR-gui-design.md` and
`docs/superpowers/plans/2026-04-30-macSubtitleOCR-gui.md`.

## When working on this codebase

- The track-extraction step lives behind a `TrackExtractor` protocol so we can
  swap to a future upstream `--track` flag without rewriting the pipeline.
- mkvtoolnix is a runtime dependency. The Drop screen probes for it and shows a
  blocking banner if missing — don't paper over the missing-tool case.
- `BundledBinary.resolve()` looks in (1) the .app bundle, (2) Bundle.module,
  (3) adjacent to the executable, (4) the vendored submodule build dir. Adding a
  new lookup location requires adding it to both `bundledPaths()` and the tests.
- Filenames use `Movie.<iso639>.srt`, with `-1`, `-2`, … suffixes on conflict.
  See `SRTFinalizer.targetURL`.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "Polish README and CLAUDE.md with full project documentation"
```

---

## Task 17: Final verification

- [ ] **Step 1: Clean build from scratch**

Run:
```bash
make clean
make build
make test
```
Expected: all green.

- [ ] **Step 2: Build and open the .app**

Run:
```bash
make app
open build/macSubtitleOCR-gui.app
```
Expected: app launches, behavior matches the user flow.

- [ ] **Step 3: Smoke test the update path**

Run: `make update`
Expected: submodule fetches latest, rebuilds, prints status showing the bumped SHA. Don't commit unless you actually want to bump.

- [ ] **Step 4: Final commit if anything changed (probably nothing)**

```bash
git status
# If clean, you're done.
```

---

## Self-Review

**Spec coverage check:**

- ✅ Input formats `.mkv` / `.sup` / `.sub` / `.idx` — DropView accepts all four; TrackProber synthetic tracks for non-MKV; OCRPipeline branches on extension.
- ✅ MKVToolNix-based track extraction behind a protocol — Task 5 (`TrackExtractor` + `MKVToolNixExtractor`).
- ✅ SwiftUI macOS app, SwiftPM-driven — Task 1 (`Package.swift`), Task 10 (`@main App`).
- ✅ Submodule vendoring + `make update` — Task 2 (Makefile, submodule).
- ✅ Drop / Tracks / Run / Done flow — Tasks 11–13.
- ✅ Cancel button + log panel — RunView (Task 13).
- ✅ Reveal-in-Finder + OCR another — DoneView (Task 13).
- ✅ Toolchain missing banner — DropView (Task 11).
- ✅ Filename rule `Movie.<lang>.srt` with conflict suffixing — `SRTFinalizer` (Task 8).
- ✅ Unit tests on pure components — Tasks 3–9 each have tests.
- ✅ `.app` bundle assembly — Task 15.
- ✅ README + CLAUDE.md — Task 16.

**Placeholder scan:** No TBDs, no "implement later," no "similar to Task N" without code. Every task has the actual code an engineer needs.

**Type consistency:**

- `Track` (id: Int, codec: Track.Codec, language: String?, name: String?) — used consistently across TrackProber, TracksView, OCRPipeline.
- `OCRRunner.Options` — used in TracksView (`@Bindable`) and OCRPipeline.
- `SubtitleJob.Phase` — `.idle / .probing / .tracks / .running(stage:) / .done(output:) / .failed(message:)` — referenced consistently in AppView, DropView, OCRPipeline, RunView, DoneView.
- `BundledBinary.resolve()` returns `URL` — consumed by `OCRRunner(binary:)`. ✓
- `MKVToolNixExtractor.extract(input:trackID:)` returns `URL` — consumed in OCRPipeline. ✓
- `SRTFinalizer.finalize(producedSRTDir:inputURL:language:)` returns `URL` — assigned to `.done(output:)`. ✓

All clean.

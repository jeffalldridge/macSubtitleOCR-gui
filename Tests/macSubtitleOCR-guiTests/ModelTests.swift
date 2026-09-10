import Foundation
import SubtitleEngine
import Testing
@testable import macSubtitleOCR_gui

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("gui-tests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("SubtitleEngineTests/Fixtures", isDirectory: true)

@Suite struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "settings-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func hasSensibleDefaults() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.outputFolder == nil)
        #expect(settings.conflictPolicy == .addSuffix)
        #expect(settings.defaultLanguages == ["en"])
        #expect(settings.correctLowercaseL)
        #expect(settings.notifyWhenDone)
        #expect(settings.checkForUpdates)
    }

    @Test func persistsChanges() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.defaultLanguages = ["ja", "en"]
        settings.invert = true
        settings.customWords = "Sintel, Shaman"
        settings.outputFolder = URL(fileURLWithPath: "/tmp/out", isDirectory: true)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.defaultLanguages == ["ja", "en"])
        #expect(reloaded.invert)
        #expect(reloaded.customWordList == ["Sintel", "Shaman"])
        #expect(reloaded.outputFolder?.path == "/tmp/out")
    }

    @Test func splitsCustomWords() {
        #expect(AppSettings.words(from: "a, b\nc,,  d ") == ["a", "b", "c", "d"])
        #expect(AppSettings.words(from: "").isEmpty)
    }
}

@Suite struct OutputNamingTests {
    private let film = URL(fileURLWithPath: "/Users/me/Movies/Film.mkv")

    @Test func basicFilename() {
        let track = TrackInfo(id: 2, format: .pgs, language: "eng")
        let url = OutputNaming.url(for: track, sourceURL: film, fallbackLanguage: nil, outputFolder: nil,
                                   conflictPolicy: .addSuffix, existing: [])
        #expect(url.path == "/Users/me/Movies/Film.eng.srt")
    }

    @Test func includesSanitizedTrackName() {
        let track = TrackInfo(id: 2, format: .pgs, language: "eng", name: "English SDH")
        let url = OutputNaming.url(for: track, sourceURL: film, fallbackLanguage: nil, outputFolder: nil,
                                   conflictPolicy: .addSuffix, existing: [])
        #expect(url.lastPathComponent == "Film.eng.english-sdh.srt")
    }

    @Test func mapsLanguagesToThreeLetterCodes() {
        let german = TrackInfo(id: 1, format: .pgs, language: "ger")
        #expect(OutputNaming.languageCode(for: german, fallback: nil) == "deu")
        let bcp = TrackInfo(id: 1, format: .pgs, language: "eng", languageBCP47: "pt-BR")
        #expect(OutputNaming.languageCode(for: bcp, fallback: nil) == "por")
        let untagged = TrackInfo(id: 1, format: .pgs)
        #expect(OutputNaming.languageCode(for: untagged, fallback: "en") == "eng")
        #expect(OutputNaming.languageCode(for: untagged, fallback: nil) == nil)
    }

    @Test func addsSuffixOnConflict() {
        let track = TrackInfo(id: 2, format: .pgs, language: "eng")
        let url = OutputNaming.url(for: track, sourceURL: film, fallbackLanguage: nil, outputFolder: nil,
                                   conflictPolicy: .addSuffix, existing: ["Film.eng.srt", "film.ENG-1.srt"])
        #expect(url.lastPathComponent == "Film.eng-2.srt")
    }

    @Test func replacePolicyKeepsThePrimaryName() {
        let track = TrackInfo(id: 2, format: .pgs, language: "eng")
        let url = OutputNaming.url(for: track, sourceURL: film, fallbackLanguage: nil, outputFolder: nil,
                                   conflictPolicy: .replace, existing: ["Film.eng.srt"])
        #expect(url.lastPathComponent == "Film.eng.srt")
    }

    @Test func usesTheChosenFolder() {
        let track = TrackInfo(id: 2, format: .pgs, language: "eng")
        let url = OutputNaming.url(for: track, sourceURL: film, fallbackLanguage: nil,
                                   outputFolder: URL(fileURLWithPath: "/tmp/subs", isDirectory: true),
                                   conflictPolicy: .addSuffix, existing: [])
        #expect(url.path == "/tmp/subs/Film.eng.srt")
    }

    @Test func sanitizes() {
        #expect(OutputNaming.sanitize("English SDH") == "english-sdh")
        #expect(OutputNaming.sanitize("Director's Commentary") == "director-s-commentary")
        #expect(OutputNaming.sanitize("  --weird-- ") == "weird")
        #expect(OutputNaming.sanitize("") == "")
        #expect(OutputNaming.sanitize("Español (Latino)") == "español-latino")
    }
}

@Suite struct ReviewCueTests {
    @Test func tracksEditsAndReviewState() {
        let cue = ReviewCue(index: 3, start: 1, end: 2, text: "Hel1o", confidence: 0.4, flagged: true)
        #expect(cue.needsReview)
        #expect(cue.number == 4)
        cue.text = "Hello"
        #expect(cue.isEdited)
        #expect(!cue.needsReview, "an edited cue has been reviewed")
        cue.revert()
        #expect(!cue.isEdited)
        #expect(cue.needsReview)
        cue.isMarkedReviewed = true
        #expect(!cue.needsReview)
        #expect(cue.srtCue == SRTCue(index: 4, start: 1, end: 2, text: "Hel1o"))
    }
}

@Suite struct UpdateCheckerTests {
    @Test func comparesVersions() {
        #expect(UpdateChecker.isNewer("v1.0.1", than: "1.0.0"))
        #expect(UpdateChecker.isNewer("1.1", than: "1.0.9"))
        #expect(UpdateChecker.isNewer("v2.0.0-beta", than: "1.9.9"))
        #expect(!UpdateChecker.isNewer("v1.0.0", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("0.9.9", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("garbage", than: "1.0.0"))
    }
}

@Suite struct StreamCacheTests {
    @Test func storesAndLoadsPGS() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = StreamCache(directory: dir)
        let track = TrackInfo(id: 1, format: .pgs)
        let key = StreamCache.key(for: fixtures.appendingPathComponent("sintel.mks"), track: track)
        #expect(key.count == 32)
        #expect(cache.cachedURLs(for: key, format: .pgs) == nil)

        let data = try Data(contentsOf: fixtures.appendingPathComponent("sintel.sup"))
        try cache.store(.pgs(data), key: key)
        let stream = try #require(try cache.loadStream(key: key, format: .pgs))
        #expect(stream.cues.count == 26)
        #expect(cache.totalBytes == Int64(data.count))
    }

    @Test func keyChangesWithTrackAndFile() {
        let url = fixtures.appendingPathComponent("sintel.mks")
        let a = StreamCache.key(for: url, track: TrackInfo(id: 1, format: .pgs))
        let b = StreamCache.key(for: url, track: TrackInfo(id: 2, format: .vobsub))
        let c = StreamCache.key(for: fixtures.appendingPathComponent("sintel.sup"), track: TrackInfo(id: 1, format: .pgs))
        #expect(a != b && a != c)
    }

    @Test func prunesBySizeOldestFirst() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = StreamCache(directory: dir)
        try cache.store(.pgs(Data(repeating: 1, count: 600)), key: "old")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-100)],
                                              ofItemAtPath: dir.appendingPathComponent("old.sup").path)
        try cache.store(.pgs(Data(repeating: 1, count: 600)), key: "new")
        cache.prune(maxBytes: 1000, maxAge: 3600)
        #expect(cache.cachedURLs(for: "old", format: .pgs) == nil)
        #expect(cache.cachedURLs(for: "new", format: .pgs) != nil)
    }

    @Test func prunesByAge() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = StreamCache(directory: dir)
        try cache.store(.vobsub(sub: Data([1]), idx: "x"), key: "stale")
        for name in ["stale.sub", "stale.idx"] {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-7200)],
                                                  ofItemAtPath: dir.appendingPathComponent(name).path)
        }
        cache.prune(maxBytes: .max, maxAge: 3600)
        #expect(cache.cachedURLs(for: "stale", format: .vobsub) == nil)
    }
}

@Suite struct FileImportTests {
    @Test func expandsFoldersToSupportedFiles() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["b.mkv", "a.sup", "notes.txt", ".hidden.mkv"] {
            try Data().write(to: dir.appendingPathComponent(name))
        }
        #expect(FileImport.expand(dir).map(\.lastPathComponent) == ["a.sup", "b.mkv"])
        #expect(FileImport.expand(dir.appendingPathComponent("notes.txt")).isEmpty)
        #expect(FileImport.expand(dir.appendingPathComponent("b.mkv")).count == 1)
    }
}

@Suite(.serialized) struct ConversionQueueTests {
    private func makeQueue() throws -> (ConversionQueue, URL) {
        let dir = try temporaryDirectory()
        let name = "queue-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.outputFolder = dir.appendingPathComponent("out", isDirectory: true)
        let queue = ConversionQueue(settings: settings, cache: StreamCache(directory: dir.appendingPathComponent("cache")))
        return (queue, dir)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 20) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func addsProbesAndSelectsDefaultTracks() async throws {
        let (queue, dir) = try makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        queue.add(urls: [fixtures.appendingPathComponent("sintel.mks"), fixtures.appendingPathComponent("sintel.mks")])
        #expect(queue.files.count == 1, "duplicates are ignored")
        await waitUntil { queue.files[0].state != .probing }

        let file = queue.files[0]
        #expect(file.tracks.count == 2)
        #expect(file.tracks.allSatisfy { $0.isIncluded }, "both tracks are English, the default language")
        #expect(file.summary == "1 PGS track · 1 VobSub track")
        #expect(queue.selection == .file(file.id))
        #expect(queue.canRun)
    }

    @Test func fallsBackToTheDefaultTrackWhenNoLanguageMatches() async throws {
        let (queue, dir) = try makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        queue.runOptions.languages = ["ja"]
        queue.add(urls: [fixtures.appendingPathComponent("sintel.mks")])
        await waitUntil { queue.files[0].state != .probing }
        let included = queue.files[0].tracks.filter(\.isIncluded)
        #expect(included.count == 1)
        #expect(included[0].info.id == 1, "the container's default track")
    }

    @Test func ignoresUnsupportedFilesAndReportsFailures() async throws {
        let (queue, dir) = try makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bogus = dir.appendingPathComponent("bogus.mkv")
        try Data(repeating: 0, count: 100).write(to: bogus)
        queue.add(urls: [dir.appendingPathComponent("x.mp4"), bogus])
        #expect(queue.files.count == 1)
        await waitUntil { queue.files[0].state != .probing }
        guard case .failed(let message) = queue.files[0].state else {
            Issue.record("expected failure")
            return
        }
        #expect(message.contains("not a Matroska"))
        #expect(!queue.canRun)
    }

    @Test func runsAndWritesSRTs() async throws {
        let (queue, dir) = try makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        queue.add(urls: [fixtures.appendingPathComponent("sintel.sup")])
        await waitUntil { queue.files[0].state != .probing }
        #expect(queue.files[0].tracks.count == 1)

        queue.run()
        #expect(queue.isRunning)
        await waitUntil { !queue.isRunning }

        guard case .finished(let summary) = queue.runState else {
            Issue.record("expected a finished run")
            return
        }
        #expect(summary.saved == 1)
        #expect(summary.failed == 0)
        let track = queue.files[0].tracks[0]
        #expect(track.status == .done)
        #expect(track.cues.count == 26)
        let output = try #require(track.outputURL)
        #expect(output.lastPathComponent == "sintel.eng.srt")
        let written = SRTFile.parse(try String(contentsOf: output, encoding: .utf8))
        #expect(written.count == 26)
        #expect(written[0].text == track.cues[0].text)
        #expect(queue.overallProgress == 1)

        // Editing a cue and saving rewrites the file.
        track.cues[0].text = "Edited line"
        queue.saveEdits(for: track)
        let rewritten = SRTFile.parse(try String(contentsOf: output, encoding: .utf8))
        #expect(rewritten[0].text == "Edited line")
    }

    @Test func cancellingMarksRemainingTracks() async throws {
        let (queue, dir) = try makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        queue.add(urls: [fixtures.appendingPathComponent("sintel.mks")])
        await waitUntil { queue.files[0].state != .probing }
        queue.run()
        try? await Task.sleep(for: .milliseconds(50))
        queue.cancel()
        await waitUntil { !queue.isRunning }
        guard case .finished(let summary) = queue.runState else {
            Issue.record("expected a finished run")
            return
        }
        #expect(summary.cancelled >= 1)
        #expect(queue.files[0].tracks.contains { $0.status == .cancelled })
    }

    @Test func clearResetsEverything() async throws {
        let (queue, dir) = try makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        queue.add(urls: [fixtures.appendingPathComponent("sintel.sup")])
        await waitUntil { queue.files[0].state != .probing }
        queue.clear()
        #expect(queue.isEmpty)
        #expect(queue.selection == nil)
        #expect(queue.runState == .idle)
    }
}

@Suite struct RecognizeSubtitlesIntentTests {
    private let tracks = [
        TrackInfo(id: 1, format: .pgs, language: "eng", isDefault: true),
        TrackInfo(id: 2, format: .pgs, language: "eng", name: "SDH"),
        TrackInfo(id: 3, format: .vobsub, language: "jpn"),
        TrackInfo(id: 4, format: .pgs, language: "eng", isForced: true),
    ]

    @Test func selectsEveryTrackMatchingTheLanguages() {
        let chosen = RecognizeSubtitlesIntent.select(from: tracks, languages: ["en"], choice: .matchingLanguage)
        #expect(chosen.map(\.id) == [1, 2, 4])
    }

    @Test func fallsBackToTheDefaultTrack() {
        let chosen = RecognizeSubtitlesIntent.select(from: tracks, languages: ["fr"], choice: .matchingLanguage)
        #expect(chosen.map(\.id) == [1])
    }

    @Test func honoursAllAndDefaultOnly() {
        #expect(RecognizeSubtitlesIntent.select(from: tracks, languages: ["en"], choice: .all).count == 4)
        #expect(RecognizeSubtitlesIntent.select(from: tracks, languages: ["en"], choice: .defaultOnly).map(\.id) == [1])
    }

    @Test func emptyTrackListSelectsNothing() {
        #expect(RecognizeSubtitlesIntent.select(from: [], languages: ["en"], choice: .matchingLanguage).isEmpty)
        #expect(RecognizeSubtitlesIntent.select(from: [], languages: ["en"], choice: .defaultOnly).isEmpty)
    }
}

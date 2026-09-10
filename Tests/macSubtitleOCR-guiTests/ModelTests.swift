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

@Suite struct SettingsMigrationTests {
    /// The shape releases up to 0.2 wrote under the old bundle identifier.
    private struct LegacyOptions: Encodable {
        var languages: String
        var invert: Bool
        var customWords: String?
        var disableICorrection: Bool
    }

    /// A defaults suite holding only what v0.2 would have written.
    private func legacyDefaults(_ options: LegacyOptions) throws -> UserDefaults {
        let name = "legacy-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defaults.set(try JSONEncoder().encode(options), forKey: AppSettings.legacyOptionsKey)
        return defaults
    }

    @Test func carriesOverPreOneZeroOptions() throws {
        let defaults = try legacyDefaults(LegacyOptions(languages: "en,jpn", invert: true,
                                                        customWords: "Sintel, Shaman", disableICorrection: false))
        let migrated = try #require(AppSettings.migratedFromLegacy(in: defaults))
        #expect(migrated.defaultLanguages == ["en", "jpn"])
        #expect(migrated.invert)
        #expect(migrated.customWords == "Sintel, Shaman")
        // Fields v0.2 never had keep their 1.0 defaults.
        #expect(migrated.conflictPolicy == .addSuffix)
        #expect(migrated.correctLowercaseL)
    }

    @Test func emptyLanguagesKeepTheDefault() throws {
        let defaults = try legacyDefaults(LegacyOptions(languages: "", invert: false,
                                                        customWords: nil, disableICorrection: false))
        let migrated = try #require(AppSettings.migratedFromLegacy(in: defaults))
        #expect(migrated.defaultLanguages == ["en"])
        #expect(migrated.customWords.isEmpty)
    }

    @Test func nothingToMigrateReturnsNil() throws {
        let name = "legacy-empty-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        #expect(AppSettings.migratedFromLegacy(in: defaults) == nil)
    }

    @Test func existingOneZeroSettingsWinOverMigration() throws {
        let defaults = try legacyDefaults(LegacyOptions(languages: "de", invert: true,
                                                        customWords: nil, disableICorrection: false))
        let first = AppSettings(defaults: defaults)
        #expect(first.defaultLanguages == ["de"], "a fresh install inherits the old options")
        first.defaultLanguages = ["fr"]

        let second = AppSettings(defaults: defaults)
        #expect(second.defaultLanguages == ["fr"], "once 1.0 has its own settings, they win")
    }
}

@Suite struct OutputNamingHostileInputTests {
    private let film = URL(fileURLWithPath: "/Users/me/Movies/Film.mkv")

    private func name(forTrackNamed trackName: String) -> String {
        OutputNaming.url(for: TrackInfo(id: 1, format: .pgs, language: "eng", name: trackName),
                         sourceURL: film, fallbackLanguage: nil, outputFolder: nil,
                         conflictPolicy: .addSuffix, existing: []).lastPathComponent
    }

    @Test func pathSeparatorsInATrackNameCannotEscapeTheFolder() {
        // Track names come out of the container, so they are untrusted.
        for hostile in ["../../etc/passwd", "/etc/passwd", "..", "../..", "a/b/c", ":evil"] {
            let produced = name(forTrackNamed: hostile)
            #expect(!produced.contains("/"), "\(hostile) produced \(produced)")
            #expect(!produced.contains(".."), "\(hostile) produced \(produced)")
            #expect(produced.hasPrefix("Film.eng"))
            #expect(produced.hasSuffix(".srt"))
        }
    }

    @Test func aVeryLongTrackNameIsTruncated() {
        let produced = name(forTrackNamed: String(repeating: "commentary ", count: 400))
        #expect(produced.utf8.count < 255)
        #expect(produced.hasPrefix("Film.eng.commentary"))
        #expect(!produced.contains("-.srt"), "no dangling dash where it was cut")
    }

    @Test func nonLatinTrackNamesSurvive() {
        #expect(OutputNaming.sanitize("日本語 コメンタリー") == "日本語-コメンタリー")
        #expect(OutputNaming.sanitize("Ελληνικά") == "ελληνικά")
    }

    @Test func aTrackNameOfOnlyPunctuationVanishes() {
        #expect(OutputNaming.sanitize("///...///") == "")
        #expect(name(forTrackNamed: "///") == "Film.eng.srt")
    }
}

@Suite(.serialized) struct PendingEditTests {
    @Test func flushWritesEditsThatTheDebounceHasNotSavedYet() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = "pending-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let queue = ConversionQueue(settings: AppSettings(defaults: defaults),
                                    cache: StreamCache(directory: dir.appendingPathComponent("cache")))

        let source = try SubtitleSource.open(fixtures.appendingPathComponent("sintel.sup"))
        let file = QueueFile(source: source)
        let track = QueueTrack(fileID: file.id, info: TrackInfo(id: 1, format: .pgs), isIncluded: true)
        file.tracks = [track]
        queue.files = [file]

        // Stand in for a finished run: cues on screen and a file on disk.
        let output = dir.appendingPathComponent("sintel.eng.srt")
        track.cues = [ReviewCue(index: 0, start: 1, end: 2, text: "originai text")]
        track.outputURL = output
        try SRTFile.render(track.cues.map(\.srtCue)).write(to: output, atomically: true, encoding: .utf8)

        // The user types a correction; the debounce has not fired.
        track.cues[0].text = "original text"
        track.hasUnsavedEdits = true
        #expect(queue.hasUnsavedEdits)

        queue.flushPendingEdits()

        let written = SRTFile.parse(try String(contentsOf: output, encoding: .utf8))
        #expect(written.first?.text == "original text")
        #expect(!track.hasUnsavedEdits)
        #expect(!queue.hasUnsavedEdits)
    }

    @Test(arguments: [false, true]) func removingOrClearingFlushesCorrections(clear: Bool) throws {
        let (queue, file, track, directory) = try pendingQueue()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = try #require(track.outputURL)
        if clear { queue.clear() } else { queue.remove(file) }
        #expect(queue.isEmpty)
        #expect(SRTFile.parse(try String(contentsOf: output, encoding: .utf8)).first?.text == "corrected")
    }

    @Test func failedSaveKeepsTheTrackAndCanBeRetried() throws {
        let (queue, file, track, directory) = try pendingQueue()
        defer { try? FileManager.default.removeItem(at: directory) }
        let validOutput = track.outputURL
        track.outputURL = directory.appendingPathComponent("missing/output.srt")
        queue.remove(file)
        #expect(queue.files.count == 1)
        #expect(queue.selection == .track(track.id))
        #expect(track.hasUnsavedEdits)
        #expect(track.saveError != nil)
        queue.clear()
        #expect(queue.files.count == 1)
        queue.run()
        #expect(!queue.isRunning)
        #expect(track.cues.first?.text == "corrected")
        track.outputURL = validOutput
        queue.saveEdits(for: track)
        #expect(!track.hasUnsavedEdits)
        #expect(track.saveError == nil)
    }

    private func pendingQueue() throws -> (ConversionQueue, QueueFile, QueueTrack, URL) {
        let directory = try temporaryDirectory()
        let defaults = try #require(UserDefaults(suiteName: "pending-removal-\(UUID())"))
        let queue = ConversionQueue(settings: AppSettings(defaults: defaults))
        let source = try SubtitleSource.open(fixtures.appendingPathComponent("sintel.sup"))
        let file = QueueFile(source: source)
        let info = try source.probe()
        file.state = .ready(info)
        let track = QueueTrack(fileID: file.id, info: TrackInfo(id: 1, format: .pgs), isIncluded: true)
        track.cues = [ReviewCue(index: 0, start: 1, end: 2, text: "original")]
        track.cues[0].text = "corrected"
        track.outputURL = directory.appendingPathComponent("output.srt")
        track.hasUnsavedEdits = true
        file.tracks = [track]
        queue.files = [file]
        return (queue, file, track, directory)
    }

    @Test func flushIsHarmlessWithNothingPending() throws {
        let name = "pending-empty-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let queue = ConversionQueue(settings: AppSettings(defaults: defaults))
        queue.flushPendingEdits()
        #expect(!queue.hasUnsavedEdits)
    }
}

@Suite struct OutputCollisionTests {
    private let film = URL(fileURLWithPath: "/Users/me/Movies/Film.mkv")

    /// An MKV with a full English track and an English forced track, neither
    /// named — the same filename by every other rule.
    private let full = TrackInfo(id: 1, format: .pgs, language: "eng")
    private let forced = TrackInfo(id: 2, format: .pgs, language: "eng", isForced: true)

    private func url(_ track: TrackInfo, policy: AppSettings.ConflictPolicy,
                     existing: Set<String>, claimed: Set<String>) -> URL {
        OutputNaming.url(for: track, sourceURL: film, fallbackLanguage: nil, outputFolder: nil,
                         conflictPolicy: policy, existing: existing, claimed: claimed)
    }

    @Test func replaceDoesNotClobberAFileThisRunJustWrote() {
        let first = url(full, policy: .replace, existing: [], claimed: [])
        #expect(first.lastPathComponent == "Film.eng.srt")

        let second = url(forced, policy: .replace, existing: [], claimed: [first.lastPathComponent])
        #expect(second.lastPathComponent != first.lastPathComponent,
                "the second track must not destroy the first")
        #expect(second.lastPathComponent == "Film.eng-1.srt")
    }

    @Test func replaceStillOverwritesWhatWasAlreadyOnDisk() {
        let produced = url(full, policy: .replace, existing: ["Film.eng.srt"], claimed: [])
        #expect(produced.lastPathComponent == "Film.eng.srt", "that is what Replace means")
    }

    @Test func addSuffixAvoidsBothDiskAndThisRun() {
        let produced = url(forced, policy: .addSuffix,
                           existing: ["Film.eng.srt"], claimed: ["Film.eng-1.srt"])
        #expect(produced.lastPathComponent == "Film.eng-2.srt")
    }
}

@Suite struct StreamCacheEvictionTests {
    @Test func aVobSubPairIsEvictedTogether() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = StreamCache(directory: dir)

        try cache.store(.vobsub(sub: Data(repeating: 1, count: 800), idx: "old"), key: "old")
        for name in ["old.sub", "old.idx"] {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-100)],
                                                  ofItemAtPath: dir.appendingPathComponent(name).path)
        }
        try cache.store(.vobsub(sub: Data(repeating: 1, count: 800), idx: "new"), key: "new")

        cache.prune(maxBytes: 1000, maxAge: 3600)

        // The older pair goes as a unit; a half-deleted pair is unusable and
        // would still count toward the cache size.
        #expect(cache.cachedURLs(for: "old", format: .vobsub) == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("old.idx").path))
        #expect(cache.cachedURLs(for: "new", format: .vobsub) != nil)
    }
}

@Suite(.serialized) struct MidRunAdditionTests {
    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 30) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func aFileAddedDuringARunIsStillConverted() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = "midrun-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.outputFolder = dir.appendingPathComponent("out", isDirectory: true)
        let queue = ConversionQueue(settings: settings,
                                    cache: StreamCache(directory: dir.appendingPathComponent("cache")))

        // Two copies of the fixture under different names, so both produce
        // their own output.
        let first = dir.appendingPathComponent("first.sup")
        let second = dir.appendingPathComponent("second.sup")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("sintel.sup"), to: first)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("sintel.sup"), to: second)

        queue.add(urls: [first])
        await waitUntil { queue.files.first?.state != .probing }
        queue.run()

        // Dropped on the window while the first file is being recognized.
        queue.add(urls: [second])
        #expect(queue.files.count == 2)

        await waitUntil { !queue.isRunning }
        guard case .finished(let summary) = queue.runState else {
            Issue.record("expected a finished run")
            return
        }
        #expect(summary.saved == 2, "the late arrival is converted too, not silently skipped")
        #expect(queue.allTracks.allSatisfy { $0.status == .done })
        #expect(Set(summary.outputs.map(\.lastPathComponent)) == ["first.eng.srt", "second.eng.srt"])
    }
}

import Foundation
import SubtitleEngine
import Testing
@testable import macSubtitleOCR_gui

@Suite struct TrackLanguageTests {
    @Test func assignmentOverridesBothSourceTagsAndCanBeReset() {
        let track = QueueTrack(fileID: UUID(),
                               info: TrackInfo(id: 4, format: .pgs, language: "eng", languageBCP47: "en-US"),
                               isIncluded: true)
        track.languageOverride = "fr"
        #expect(track.effectiveLanguageTag == "fr")
        #expect(track.info.preferredLanguageTag == "en-US")
        #expect(OutputNaming.languageCode(for: track.info, fallback: "en", override: track.languageOverride) == "fra")
        let resolved = TextRecognizer.resolvedLanguages(for: track.effectiveLanguageTag,
                                                       options: RecognitionOptions(languages: ["en"]),
                                                       supported: [.init(identifier: "en"), .init(identifier: "fr")])
        #expect(resolved.first?.languageCode?.identifier == "fr")
        track.languageOverride = nil
        #expect(track.effectiveLanguageTag == "en-US")
    }

    @Test func untaggedTrackUsesAssignedLanguageForItsOutput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("SubtitleEngineTests/Fixtures/sintel.sup")
        let file = QueueFile(source: try SubtitleSource.open(fixture))
        let track = QueueTrack(fileID: file.id, info: TrackInfo(id: 1, format: .pgs), isIncluded: true)
        #expect(track.effectiveLanguageTag == nil)
        track.languageOverride = "de"
        let cues = [ReviewCue(index: 0, start: 0, end: 1, text: "Hallo")]
        let output = try ConversionRunner.writeSRT(cues: cues, for: track, in: file,
                                                  options: RunOptions(languages: ["en"], outputFolder: directory))
        #expect(output.lastPathComponent == "sintel.deu.srt")
        #expect(track.title == track.languageName)
        track.outputURL = output
        track.languageOverride = "fr"
        let savedAgain = try ConversionRunner.writeSRT(cues: cues, for: track, in: file,
                                                      options: RunOptions(outputFolder: directory))
        #expect(savedAgain == output, "Edits keep updating the existing SRT until a new conversion is requested")
    }
}

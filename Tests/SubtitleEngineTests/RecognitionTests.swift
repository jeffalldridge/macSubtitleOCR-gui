import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct RecognizedCueTests {
    private func cue(text: String, confidences: [Float], hadBitmap: Bool = true) -> RecognizedCue {
        RecognizedCue(index: 0, start: 0, end: 1, text: text,
                      lines: confidences.map { RecognizedLine(text: "x", confidence: $0) },
                      hadBitmap: hadBitmap)
    }

    @Test func confidenceIsTheLowestLine() {
        #expect(cue(text: "a", confidences: [1, 0.5, 0.9]).confidence == 0.5)
    }

    @Test func reviewRules() {
        #expect(!cue(text: "Hello", confidences: [1]).needsReview)
        #expect(cue(text: "Hello", confidences: [0.3]).needsReview)
        #expect(cue(text: "", confidences: []).needsReview, "a bitmap that produced nothing")
        #expect(!cue(text: "", confidences: [], hadBitmap: false).needsReview, "nothing to read")
        #expect(cue(text: "Hello", confidences: [1, 0.59]).needsReview)
        #expect(!cue(text: "Hello", confidences: [1, 0.6]).needsReview)
    }
}

@Suite struct TextRecognizerTests {
    @Test func correctsLowercaseLToI() {
        #expect(TextRecognizer.correctLowercaseL("l am here, l think.") == "I am here, I think.")
        #expect(TextRecognizer.correctLowercaseL("Hello world") == "Hello world")
        #expect(TextRecognizer.correctLowercaseL("l'll go") == "I'll go")
        #expect(TextRecognizer.correctLowercaseL("all l see") == "all I see")
    }

    @Test func listsSupportedLanguages() async {
        let languages = await TextRecognizer.supportedLanguages()
        #expect(languages.count >= 10)
        #expect(languages.contains { $0.languageCode?.identifier == "en" })
    }

    @Test func resolvesLanguagesForATrack() async {
        let supported = await TextRecognizer.supportedLanguages()
        var options = RecognitionOptions()
        options.languages = ["en"]
        let resolved = TextRecognizer.resolvedLanguages(for: "jpn", options: options, supported: supported)
        #expect(resolved.first?.languageCode?.identifier == "ja", "the track's language comes first")
        #expect(resolved.contains { $0.languageCode?.identifier == "en" })

        let unknown = TextRecognizer.resolvedLanguages(for: nil, options: options, supported: supported)
        #expect(unknown.map { $0.languageCode?.identifier } == ["en"])
    }
}

@Suite(.serialized) struct TrackConverterTests {
    private func referenceText() throws -> String {
        let text = try String(contentsOf: Fixtures.sintelSRT, encoding: .utf8)
        return SRTFile.parse(text).map(\.text).joined(separator: "\n")
    }

    private func convert(_ stream: any SubtitleStream) async throws -> (cues: [RecognizedCue], events: Int) {
        var options = RecognitionOptions()
        options.languages = ["en"]
        var finished: [RecognizedCue]?
        var events = 0
        var indexed: Int?
        var lastProgress = 0
        for try await event in TrackConverter.run(stream: stream, options: options) {
            events += 1
            switch event {
            case .indexed(let count): indexed = count
            case .progress(let done, let total):
                #expect(done > lastProgress && done <= total)
                lastProgress = done
            case .cue: break
            case .finished(let cues): finished = cues
            }
        }
        #expect(indexed == stream.cues.count)
        #expect(lastProgress == stream.cues.count)
        let cues = try #require(finished)
        return (cues, events)
    }

    @Test func recognizesSintelPGS() async throws {
        let stream = try PGSStream(url: Fixtures.sintelSUP)
        let (cues, _) = try await convert(stream)
        #expect(cues.count == 26)
        #expect(cues.map(\.index) == Array(0..<26), "results arrive in cue order")
        let allHadBitmaps = cues.allSatisfy { $0.hadBitmap }
        #expect(allHadBitmaps)
        let text = cues.map(\.text).joined(separator: "\n")
        let similarity = TextSimilarity.percentage(text, try referenceText())
        #expect(similarity >= 95, "similarity \(similarity)%")
        #expect(cues.filter(\.needsReview).count <= 2)
        #expect(cues[0].start == 107.25)
        #expect(cues[0].confidence > 0.5)
    }

    @Test func recognizesSintelVobSub() async throws {
        let stream = try VobSubStream(subURL: Fixtures.sintelSUB, idxURL: Fixtures.sintelIDX)
        let (cues, _) = try await convert(stream)
        #expect(cues.count == 26)
        let text = cues.map(\.text).joined(separator: "\n")
        let similarity = TextSimilarity.percentage(text, try referenceText())
        #expect(similarity >= 92, "similarity \(similarity)%")
    }

    @Test func cancellationStopsTheRun() async throws {
        let stream = try PGSStream(url: Fixtures.sintelSUP)
        var options = RecognitionOptions()
        options.languages = ["en"]
        let task = Task { () -> (sawFinished: Bool, events: Int) in
            var events = 0
            var sawFinished = false
            for try await event in TrackConverter.run(stream: stream, options: options) {
                events += 1
                if case .finished = event { sawFinished = true }
                if case .cue = event { withUnsafeCurrentTask { $0?.cancel() } }
            }
            return (sawFinished, events)
        }
        let result = try await task.value
        #expect(!result.sawFinished)
        #expect(result.events < 26)
    }
}

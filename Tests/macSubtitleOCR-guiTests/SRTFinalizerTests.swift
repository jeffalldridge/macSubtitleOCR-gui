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

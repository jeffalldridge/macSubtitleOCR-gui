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

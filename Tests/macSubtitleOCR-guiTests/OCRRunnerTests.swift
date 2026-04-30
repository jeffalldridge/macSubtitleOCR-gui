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

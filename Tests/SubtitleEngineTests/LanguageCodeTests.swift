import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct LanguageCodeTests {
    @Test func mapsTerminologyAndBibliographicCodes() {
        #expect(LanguageCode.alpha2("eng") == "en")
        #expect(LanguageCode.alpha2("jpn") == "ja")
        #expect(LanguageCode.alpha2("ger") == "de")
        #expect(LanguageCode.alpha2("fre") == "fr")
        #expect(LanguageCode.alpha2("chi") == "zh")
        #expect(LanguageCode.alpha2("dut") == "nl")
        #expect(LanguageCode.alpha2("en") == "en")
        #expect(LanguageCode.alpha2("en-US") == "en")
        #expect(LanguageCode.alpha2("ENG") == "en")
    }

    @Test func unknownAndUndeterminedAreNil() {
        #expect(LanguageCode.alpha2("und") == nil)
        #expect(LanguageCode.alpha2("") == nil)
        #expect(LanguageCode.alpha2(nil) == nil)
        #expect(LanguageCode.alpha2("xxx") == nil)
        #expect(LanguageCode.alpha2("mis") == nil)
    }

    @Test func producesThreeLetterCodesForFilenames() {
        #expect(LanguageCode.alpha3("en") == "eng")
        #expect(LanguageCode.alpha3("eng") == "eng")
        #expect(LanguageCode.alpha3("ger") == "deu")
        #expect(LanguageCode.alpha3("pt-BR") == "por")
        #expect(LanguageCode.alpha3("und") == nil)
    }

    @Test func displayNames() {
        #expect(LanguageCode.displayName("jpn") == "Japanese")
        #expect(LanguageCode.displayName("ger") == "German")
        #expect(LanguageCode.displayName("en-US") == "English")
        #expect(LanguageCode.displayName(nil) == "Unknown language")
        #expect(LanguageCode.displayName("und") == "Unknown language")
        #expect(LanguageCode.displayName("xxx") == "xxx", "unknown codes are shown verbatim")
    }

    @Test func picksARecognitionLanguageFromTheSupportedList() {
        let supported = ["en", "fr", "zh", "zh-TW", "pt"].map { Locale.Language(identifier: $0) }
        #expect(LanguageCode.recognitionLanguage("eng", supported: supported)?.minimalIdentifier == "en")
        #expect(LanguageCode.recognitionLanguage("ger", supported: supported) == nil)
        #expect(LanguageCode.recognitionLanguage("zho", supported: supported)?.minimalIdentifier == "zh")
        #expect(LanguageCode.recognitionLanguage("zh-Hant", supported: supported)?.minimalIdentifier == "zh-TW")
        #expect(LanguageCode.recognitionLanguage("zh-TW", supported: supported)?.minimalIdentifier == "zh-TW")
        #expect(LanguageCode.recognitionLanguage("pt-BR", supported: supported)?.minimalIdentifier == "pt")
        #expect(LanguageCode.recognitionLanguage(nil, supported: supported) == nil)
    }
}

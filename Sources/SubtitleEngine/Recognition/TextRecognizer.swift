import CoreGraphics
import Foundation
import Vision

/// Apple Vision text recognition for one subtitle bitmap at a time.
public struct TextRecognizer: Sendable {
    public let languages: [Locale.Language]
    public let customWords: [String]
    public let automaticLanguageDetection: Bool

    public init(languages: [Locale.Language], customWords: [String] = [], automaticLanguageDetection: Bool = false) {
        self.languages = languages
        self.customWords = customWords
        self.automaticLanguageDetection = automaticLanguageDetection
    }

    /// Languages Vision can recognize on this Mac.
    public static func supportedLanguages() async -> [Locale.Language] {
        await RecognizeTextRequest().supportedRecognitionLanguages
    }

    /// The language list for a track: its own language first (when Vision
    /// supports it), then the user's list, de-duplicated.
    public static func resolvedLanguages(for trackLanguage: String?,
                                         options: RecognitionOptions,
                                         supported: [Locale.Language]) -> [Locale.Language] {
        var result: [Locale.Language] = []
        if let own = LanguageCode.recognitionLanguage(trackLanguage, supported: supported) {
            result.append(own)
        }
        for identifier in options.languages {
            if let match = LanguageCode.recognitionLanguage(identifier, supported: supported),
               !result.contains(where: { $0.languageCode == match.languageCode && $0.script == match.script }) {
                result.append(match)
            }
        }
        return result
    }

    /// Recognize the text in `image`, top line first.
    public func recognize(_ image: CGImage) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        request.automaticallyDetectsLanguage = automaticLanguageDetection && languages.isEmpty
        if !customWords.isEmpty { request.customWords = customWords }

        let observations = try await request.perform(on: image)
        // Vision's coordinate origin is bottom-left; higher y is higher on the image.
        let ordered = observations.sorted { $0.boundingBox.cgRect.midY > $1.boundingBox.cgRect.midY }
        return ordered.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string, confidence: candidate.confidence)
        }
    }

    /// Vision often reads a capital `I` in sans-serif fonts as a lowercase `l`.
    /// Replace a standalone `l` (including before an apostrophe) with `I`.
    public static func correctLowercaseL(_ text: String) -> String {
        text.replacingOccurrences(of: #"\bl\b"#, with: "I", options: .regularExpression)
    }
}

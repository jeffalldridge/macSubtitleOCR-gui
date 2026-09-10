import Foundation

/// How text recognition should run.
public struct RecognitionOptions: Sendable, Equatable, Codable {
    /// BCP 47 language identifiers in priority order (`["en", "ja"]`).
    /// A track's own language is placed ahead of these when known.
    public var languages: [String]
    /// Words the recognizer should prefer (character names, places).
    public var customWords: [String]
    /// Render white text on black instead of black on white before recognition.
    public var invert: Bool
    /// Replace a lone lowercase `l` with `I` in English text.
    public var correctLowercaseL: Bool
    /// Let Vision detect the language when a track has none.
    public var automaticLanguageDetection: Bool
    /// Cues recognized at the same time.
    public var maxConcurrency: Int

    public init(languages: [String] = ["en"],
                customWords: [String] = [],
                invert: Bool = false,
                correctLowercaseL: Bool = true,
                automaticLanguageDetection: Bool = true,
                maxConcurrency: Int = 4) {
        self.languages = languages
        self.customWords = customWords
        self.invert = invert
        self.correctLowercaseL = correctLowercaseL
        self.automaticLanguageDetection = automaticLanguageDetection
        self.maxConcurrency = maxConcurrency
    }
}

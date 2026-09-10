import Foundation
import SubtitleEngine

/// Options for the current queue. Seeded from `AppSettings`, edited in the
/// inspector, and applied to every track in the run.
struct RunOptions: Equatable {
    var languages: [String]
    var customWords: String
    var invert: Bool
    var correctLowercaseL: Bool
    var outputFolder: URL?
    var conflictPolicy: AppSettings.ConflictPolicy

    init(settings: AppSettings) {
        languages = settings.defaultLanguages
        customWords = settings.customWords
        invert = settings.invert
        correctLowercaseL = settings.correctLowercaseL
        outputFolder = settings.outputFolder
        conflictPolicy = settings.conflictPolicy
    }

    init(languages: [String] = ["en"],
         customWords: String = "",
         invert: Bool = false,
         correctLowercaseL: Bool = true,
         outputFolder: URL? = nil,
         conflictPolicy: AppSettings.ConflictPolicy = .addSuffix) {
        self.languages = languages
        self.customWords = customWords
        self.invert = invert
        self.correctLowercaseL = correctLowercaseL
        self.outputFolder = outputFolder
        self.conflictPolicy = conflictPolicy
    }

    var recognition: RecognitionOptions {
        RecognitionOptions(languages: languages,
                           customWords: AppSettings.words(from: customWords),
                           invert: invert,
                           correctLowercaseL: correctLowercaseL,
                           automaticLanguageDetection: true)
    }

    /// The first language, as a fallback code for filenames of untagged tracks.
    var fallbackLanguage: String? { languages.first }
}

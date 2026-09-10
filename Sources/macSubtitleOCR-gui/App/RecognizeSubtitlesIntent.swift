import AppIntents
import Foundation
import UniformTypeIdentifiers
import SubtitleEngine

/// Shortcuts and Spotlight: recognize subtitle files without opening a window.
struct RecognizeSubtitlesIntent: AppIntent {
    static let title: LocalizedStringResource = "Recognize Subtitles"
    static let description = IntentDescription(
        "Converts PGS or VobSub bitmap subtitles into SRT text files using Apple's Vision framework.",
        categoryName: "Subtitles",
        searchKeywords: ["subtitle", "srt", "ocr", "pgs", "vobsub", "blu-ray"]
    )
    static let openAppWhenRun = false

    @Parameter(title: "Files",
               description: "MKV, MKS, SUP, or SUB/IDX files.",
               supportedContentTypes: [.movie, .data])
    var files: [IntentFile]

    @Parameter(title: "Languages",
               description: "Comma-separated language codes to recognize, such as “en,ja”. Leave empty to use the app’s default.")
    var languages: String?

    @Parameter(title: "Tracks",
               description: "Which subtitle tracks to convert.",
               default: TrackChoice.matchingLanguage)
    var trackChoice: TrackChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Recognize subtitles in \(\.$files)") {
            \.$languages
            \.$trackChoice
        }
    }

    enum TrackChoice: String, AppEnum {
        case matchingLanguage
        case all
        case defaultOnly

        static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tracks")
        static let caseDisplayRepresentations: [TrackChoice: DisplayRepresentation] = [
            .matchingLanguage: "Tracks matching the languages",
            .all: "All bitmap subtitle tracks",
            .defaultOnly: "The default track only",
        ]
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let requested = languages
            .map { AppSettings.words(from: $0) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? AppSettings().defaultLanguages

        var produced: [IntentFile] = []
        for file in files {
            guard let url = file.fileURL else { continue }
            let outputs = try await Self.recognize(url: url, languages: requested, choice: trackChoice)
            for output in outputs {
                produced.append(IntentFile(fileURL: output, filename: output.lastPathComponent))
            }
        }
        return .result(value: produced)
    }

    /// Headless equivalent of a queue run for one file.
    ///
    /// `nonisolated`, and every synchronous step runs off the main actor:
    /// probing and extraction are file work, and running them on the main
    /// actor freezes the window while a shortcut is processing.
    nonisolated static func recognize(url: URL, languages: [String], choice: TrackChoice) async throws -> [URL] {
        let source = try SubtitleSource.open(url)
        let info = try await Task.detached(priority: .userInitiated) { try source.probe() }.value
        let tracks = select(from: info.tracks, languages: languages, choice: choice)
        guard !tracks.isEmpty else { return [] }

        let options = RecognitionOptions(languages: languages)
        var outputs: [URL] = []
        let folder = source.primaryURL.deletingLastPathComponent()
        var claimed: Set<String> = []

        for track in tracks {
            let stream = try await Task.detached(priority: .userInitiated) {
                try source.loadStream(for: track, progress: nil)
            }.value
            var recognized: [RecognizedCue] = []
            for try await event in TrackConverter.run(stream: stream, options: options,
                                                      trackLanguage: track.preferredLanguageTag) {
                if case .finished(let cues) = event { recognized = cues }
            }
            let ends = SRTTiming.resolveEnds(starts: recognized.map(\.start), ends: recognized.map(\.end))
            let cues = zip(recognized, ends).enumerated().map { index, pair in
                SRTCue(index: index + 1, start: pair.0.start, end: pair.1, text: pair.0.text)
            }
            let destination = OutputNaming.url(for: track,
                                               sourceURL: source.primaryURL,
                                               fallbackLanguage: languages.first,
                                               outputFolder: nil,
                                               conflictPolicy: .addSuffix,
                                               existing: OutputNaming.existingNames(in: folder),
                                               claimed: claimed)
            try SRTFile.render(cues).write(to: destination, atomically: true, encoding: .utf8)
            claimed.insert(destination.lastPathComponent)
            outputs.append(destination)
        }
        return outputs
    }

    nonisolated static func select(from tracks: [TrackInfo], languages: [String], choice: TrackChoice) -> [TrackInfo] {
        switch choice {
        case .all:
            return tracks
        case .defaultOnly:
            return [tracks.first { $0.isDefault && !$0.isForced } ?? tracks.first].compactMap { $0 }
        case .matchingLanguage:
            let wanted = Set(languages.compactMap { LanguageCode.alpha2($0) })
            let matches = tracks.filter { track in
                guard let code = LanguageCode.alpha2(track.preferredLanguageTag) else { return false }
                return wanted.contains(code)
            }
            if !matches.isEmpty { return matches }
            return [tracks.first { $0.isDefault && !$0.isForced } ?? tracks.first].compactMap { $0 }
        }
    }
}

struct SubtitleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecognizeSubtitlesIntent(),
            phrases: [
                "Recognize subtitles with \(.applicationName)",
                "Convert subtitles with \(.applicationName)",
            ],
            shortTitle: "Recognize Subtitles",
            systemImageName: "text.viewfinder"
        )
    }
}

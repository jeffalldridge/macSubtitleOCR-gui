import AppKit
import SubtitleEngine
import SwiftUI
@preconcurrency import Translation

/// Export a translated copy of a recognized track using the on-device
/// Translation framework.
struct TranslationExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConversionQueue.self) private var queue

    let track: QueueTrack
    let file: QueueFile

    @State private var target: Locale.Language = Locale.Language(identifier: "es")
    @State private var supported: [Locale.Language] = []
    @State private var configuration: TranslationSession.Configuration?
    @State private var progress: Double = 0
    @State private var isTranslating = false
    @State private var result: Result<URL, Error>?

    private var source: Locale.Language? {
        LanguageCode.language(track.effectiveLanguageTag)
            ?? queue.runOptions.languages.first.flatMap { LanguageCode.language($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Translate “\(track.title)”")
                .font(.title3.weight(.semibold))
            Text("Translation runs on this Mac using Apple’s Translation framework. The first use of a language pair may download a language pack.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                LabeledContent("From", value: source.map(LanguageChecklist.name(for:)) ?? "Unknown language")
                Picker("To", selection: $target) {
                    ForEach(supported, id: \.maximalIdentifier) { language in
                        Text(LanguageChecklist.name(for: language)).tag(language)
                    }
                }
                LabeledContent("Saves as") {
                    Text(outputName)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.columns)

            if isTranslating {
                ProgressView(value: progress) {
                    Text("Translating \(track.cues.count.formatted()) cues…")
                }
            }

            switch result {
            case .success(let url):
                Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case nil:
                EmptyView()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if case .success(let url) = result {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Translate") {
                        result = nil
                        progress = 0
                        isTranslating = true
                        configuration = TranslationSession.Configuration(source: source, target: target)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isTranslating || track.cues.isEmpty || source == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            let all = await Task.detached { await LanguageAvailability().supportedLanguages }.value
            supported = all.sorted { LanguageChecklist.name(for: $0) < LanguageChecklist.name(for: $1) }
            if let source, let first = supported.first(where: { $0.languageCode != source.languageCode }) {
                target = first
            }
        }
        .translationTask(configuration) { session in
            await translate(with: session)
        }
    }

    private var outputName: String {
        let code = LanguageCode.alpha3(target.minimalIdentifier)
        return OutputNaming.filename(base: file.url.deletingPathExtension().lastPathComponent,
                                     languageCode: code, trackName: track.info.name)
    }

    private func translate(with session: TranslationSession) async {
        defer { isTranslating = false; configuration = nil }
        do {
            let cues = track.cues
            let texts = cues.map { (index: $0.index, text: $0.text) }
            let translated = try await Self.translateAll(session: session, texts: texts) { value in
                progress = value
            }
            let srtCues = cues.map { cue in
                SRTCue(index: cue.number, start: cue.start, end: cue.end, text: translated[cue.index] ?? cue.text)
            }
            let folder = queue.runOptions.outputFolder ?? file.url.deletingLastPathComponent()
            let url = OutputNaming.url(for: TrackInfo(id: track.info.id, format: track.info.format,
                                                      language: target.minimalIdentifier, name: track.info.name),
                                       sourceURL: file.url,
                                       fallbackLanguage: nil,
                                       outputFolder: queue.runOptions.outputFolder,
                                       conflictPolicy: queue.runOptions.conflictPolicy,
                                       existing: OutputNaming.existingNames(in: folder))
            try SRTFile.render(srtCues).write(to: url, atomically: true, encoding: .utf8)
            result = .success(url)
        } catch {
            result = .failure(error)
        }
    }

    /// Translate in batches of 50 off the main actor.
    nonisolated private static func translateAll(session: TranslationSession,
                                                 texts: [(index: Int, text: String)],
                                                 progress: @MainActor @Sendable (Double) -> Void) async throws -> [Int: String] {
        let requests = texts.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: "\($0.index)") }
        let batches = stride(from: 0, to: requests.count, by: 50).map { Array(requests[$0..<min($0 + 50, requests.count)]) }
        var translated: [Int: String] = [:]
        for (i, batch) in batches.enumerated() {
            let responses = try await session.translations(from: batch)
            for response in responses {
                if let id = response.clientIdentifier, let index = Int(id) {
                    translated[index] = response.targetText
                }
            }
            await progress(Double(i + 1) / Double(batches.count))
        }
        return translated
    }
}

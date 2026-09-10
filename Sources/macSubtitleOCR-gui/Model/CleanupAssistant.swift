import Foundation
import FoundationModels

/// Suggests fixes for flagged cues using the on-device language model.
/// Suggestions are never applied automatically.
@available(macOS 26, *)
final class CleanupAssistant {
    struct Suggestion: Identifiable, Equatable {
        let cueIndex: Int
        let original: String
        let suggested: String
        var id: Int { cueIndex }
    }

    @Generable(description: "A subtitle cue with OCR mistakes corrected.")
    struct CorrectedCue {
        @Guide(description: "The cue number exactly as given.")
        let number: Int
        @Guide(description: "The corrected text. Keep line breaks as \\n. Return the text unchanged if it is already correct.")
        let text: String
    }

    @Generable
    struct CorrectedBatch {
        let cues: [CorrectedCue]
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: "This Mac does not support Apple Intelligence."
            case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in System Settings to use this."
            case .modelNotReady: "The language model is still downloading."
            @unknown default: "Apple Intelligence is not available right now."
            }
        }
    }

    nonisolated static let batchSize = 20

    /// Split cues into batches the model can handle in one request.
    nonisolated static func batches(_ cues: [(index: Int, text: String)]) -> [[(index: Int, text: String)]] {
        stride(from: 0, to: cues.count, by: batchSize).map { Array(cues[$0..<min($0 + batchSize, cues.count)]) }
    }

    /// Only cues whose text actually changed become suggestions.
    nonisolated static func suggestions(from corrected: [CorrectedCue],
                                        originals: [Int: String]) -> [Suggestion] {
        corrected.compactMap { cue in
            guard let original = originals[cue.number] else { return nil }
            let suggested = cue.text.replacingOccurrences(of: "\\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !suggested.isEmpty, suggested != original else { return nil }
            return Suggestion(cueIndex: cue.number, original: original, suggested: suggested)
        }
        .sorted { $0.cueIndex < $1.cueIndex }
    }

    func suggestions(for cues: [ReviewCue], language: String?, progress: @MainActor (Double) -> Void) async throws -> [Suggestion] {
        let languageName = language.map { " The subtitles are in \($0)." } ?? ""
        let session = LanguageModelSession(instructions: """
            You fix optical character recognition mistakes in movie subtitles.\(languageName)
            Only correct errors that come from misread characters: confusions such as l/I/1, O/0, rn/m,
            missing or doubled letters, stray punctuation, and wrong spacing.
            Never change meaning, wording, capitalization style, or line breaks. Never translate.
            If a cue is already correct, return it unchanged.
            """)
        let inputs = cues.map { (index: $0.index, text: $0.text) }
        let originals = Dictionary(uniqueKeysWithValues: inputs.map { ($0.index, $0.text) })
        var results: [CorrectedCue] = []
        let batches = Self.batches(inputs)
        for (i, batch) in batches.enumerated() {
            try Task.checkCancellation()
            let listing = batch.map { "\($0.index): \($0.text.replacingOccurrences(of: "\n", with: "\\n"))" }
                .joined(separator: "\n")
            let prompt = "Correct these cues. Answer with every cue, numbered exactly as given.\n\n\(listing)"
            let response = try await session.respond(to: prompt, generating: CorrectedBatch.self)
            results.append(contentsOf: response.content.cues)
            await progress(Double(i + 1) / Double(batches.count))
        }
        return Self.suggestions(from: results, originals: originals)
    }
}

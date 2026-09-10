import SwiftUI

/// Before/after suggestions from Apple Intelligence for flagged cues.
@available(macOS 26, *)
struct CleanupSuggestionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Environment(ConversionQueue.self) private var queue

    let track: QueueTrack

    @State private var suggestions: [CleanupAssistant.Suggestion] = []
    @State private var accepted: Set<Int> = []
    @State private var progress: Double = 0
    @State private var phase: Phase = .working
    @State private var task: Task<[CleanupAssistant.Suggestion], Error>?

    private enum Phase: Equatable {
        case working
        case ready
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Clean Up with Apple Intelligence", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))
                Spacer()
                if phase == .working {
                    ProgressView(value: progress).frame(width: 140)
                }
            }
            Text("Suggestions for the \(flaggedCount) flagged cues, from the on-device model. Nothing changes until you accept it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                switch phase {
                case .working where suggestions.isEmpty:
                    ContentUnavailableView("Reading the flagged cues…", systemImage: "sparkles")
                case .failed(let message):
                    ContentUnavailableView("Couldn’t get suggestions", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                default:
                    if suggestions.isEmpty {
                        ContentUnavailableView("Nothing to change", systemImage: "checkmark.circle",
                                               description: Text("The model found no character mistakes in the flagged cues."))
                    } else {
                        suggestionList
                    }
                }
            }
            .frame(minHeight: 240)

            HStack {
                Text(suggestions.isEmpty ? "" : "\(accepted.count) of \(suggestions.count) accepted")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { task?.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Accept All") { accepted = Set(suggestions.map(\.id)) }
                    .disabled(suggestions.isEmpty || accepted.count == suggestions.count)
                Button("Apply") { apply() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(accepted.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640, height: 480)
        .task { await run() }
    }

    private var flaggedCount: Int { track.cues.filter(\.needsReview).count }

    private var suggestionList: some View {
        List(suggestions) { suggestion in
            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { accepted.contains(suggestion.id) },
                    set: { on in if on { accepted.insert(suggestion.id) } else { accepted.remove(suggestion.id) } }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cue \(suggestion.cueIndex + 1)").font(.caption).foregroundStyle(.secondary)
                    Text(suggestion.original).strikethrough().foregroundStyle(.secondary)
                    Text(suggestion.suggested)
                }
                .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        }
    }

    /// Awaited from `.task`, so SwiftUI cancels it when the sheet closes.
    private func run() async {
        let flagged = track.cues.filter(\.needsReview)
        let language = track.languageName == "Unknown language" ? nil : track.languageName
        let work = Task {
            try await CleanupAssistant().suggestions(for: flagged, language: language) { value in
                progress = value
            }
        }
        task = work
        defer { task = nil }
        do {
            let found = try await work.value
            suggestions = found
            accepted = Set(found.map(\.id))
            phase = .ready
        } catch is CancellationError {
            // The sheet went away.
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply() {
        let byIndex = Dictionary(uniqueKeysWithValues: track.cues.map { ($0.index, $0) })
        let applied = suggestions.filter { accepted.contains($0.id) }
        for suggestion in applied {
            byIndex[suggestion.cueIndex]?.text = suggestion.suggested
        }
        // One undo step for the whole batch: accepting forty suggestions and
        // then wanting them back should not mean forty separate undos.
        if let undoManager, !applied.isEmpty {
            let cues = applied.compactMap { byIndex[$0.cueIndex] }
            let before = applied.map(\.original)
            undoManager.registerUndo(withTarget: track) { target in
                for (cue, text) in zip(cues, before) { cue.text = text }
                Task { @MainActor in queue.saveEdits(for: target) }
            }
            undoManager.setActionName("Clean Up Cues")
        }
        queue.saveEdits(for: track)
        dismiss()
    }
}

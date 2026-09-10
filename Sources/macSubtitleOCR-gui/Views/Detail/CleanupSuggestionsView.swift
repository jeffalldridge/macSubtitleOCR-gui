import SwiftUI

/// Before/after suggestions from Apple Intelligence for flagged cues.
@available(macOS 26, *)
struct CleanupSuggestionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConversionQueue.self) private var queue

    let track: QueueTrack

    @State private var suggestions: [CleanupAssistant.Suggestion] = []
    @State private var accepted: Set<Int> = []
    @State private var progress: Double = 0
    @State private var phase: Phase = .working
    @State private var task: Task<Void, Never>?

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
        .task { run() }
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

    private func run() {
        let flagged = track.cues.filter(\.needsReview)
        let language = track.languageName == "Unknown language" ? nil : track.languageName
        task = Task {
            do {
                let found = try await CleanupAssistant().suggestions(for: flagged, language: language) { value in
                    progress = value
                }
                suggestions = found
                accepted = Set(found.map(\.id))
                phase = .ready
            } catch is CancellationError {
                // dismissed
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func apply() {
        let byIndex = Dictionary(uniqueKeysWithValues: track.cues.map { ($0.index, $0) })
        for suggestion in suggestions where accepted.contains(suggestion.id) {
            byIndex[suggestion.cueIndex]?.text = suggestion.suggested
        }
        queue.saveEdits(for: track)
        dismiss()
    }
}

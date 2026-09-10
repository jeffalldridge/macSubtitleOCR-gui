import SubtitleEngine
import SwiftUI

/// A single track's language, separate from the queue-wide recognition hints.
/// Plain model inputs keep this safe inside a Table's separate hosting context.
struct TrackLanguagePicker: View {
    @Bindable var track: QueueTrack
    let isRunning: Bool
    private let catalog = TrackLanguageCatalog.shared

    var body: some View {
        Menu {
            Picker("Track language", selection: $track.languageOverride) {
                Text(sourceLabel).tag(String?.none)
                if let chosen = track.languageOverride,
                   !catalog.languages.contains(where: { $0.minimalIdentifier == chosen }) {
                    Text(track.languageName).tag(Optional(chosen))
                }
                ForEach(catalog.languages, id: \.minimalIdentifier) { language in
                    Text(LanguageChecklist.name(for: language)).tag(Optional(language.minimalIdentifier))
                }
            }
            .pickerStyle(.inline)
            if catalog.languages.isEmpty {
                Text("Loading languages…")
            }
            if track.outputURL != nil {
                Divider()
                Text("Applies to the next conversion. The saved SRT is unchanged.")
            }
        } label: {
            Text(LanguageCode.language(track.effectiveLanguageTag) == nil ? "Assign Language…" : track.languageName)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderlessButton)
        .disabled(isRunning)
        .help("Set this track’s language for recognition, translation, and the next subtitle filename.")
        .accessibilityLabel("Track language")
        .accessibilityValue(track.languageName)
        .task { await catalog.load() }
    }

    private var sourceLabel: String {
        LanguageCode.language(track.info.preferredLanguageTag) == nil
            ? "Unassigned (use recognition hints)"
            : "From File: \(LanguageCode.displayName(track.info.preferredLanguageTag))"
    }
}

/// Fetch Vision's language list once, shared by queue cells and the detail header.
@Observable
final class TrackLanguageCatalog {
    static let shared = TrackLanguageCatalog()
    private(set) var languages: [Locale.Language] = []
    @ObservationIgnored private var loading: Task<[Locale.Language], Never>?

    func load() async {
        guard languages.isEmpty else { return }
        let task: Task<[Locale.Language], Never>
        if let loading {
            task = loading
        } else {
            task = Task { await TextRecognizer.supportedLanguages() }
            loading = task
        }
        languages = await task.value.sorted {
            LanguageChecklist.name(for: $0).localizedStandardCompare(LanguageChecklist.name(for: $1)) == .orderedAscending
        }
        loading = nil
    }
}

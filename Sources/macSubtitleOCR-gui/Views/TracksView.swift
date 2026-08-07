import SwiftUI

struct TracksView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var showAdvanced = false
    @State private var filterQuery = ""
    @FocusState private var filterFocused: Bool

    /// Above this many tracks a filter field earns its place in the layout.
    private static let filterThreshold = 6

    var body: some View {
        @Bindable var job = job

        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the subtitle tracks to convert")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if job.tracks.count > Self.filterThreshold {
                trackFilterField
            }

            trackList

            HStack(spacing: 12) {
                Button("Select All\(filterQuery.isEmpty ? "" : " Visible")") {
                    job.selectedTrackIDs.formUnion(filteredTracks.map(\.id))
                }
                .disabled(filteredTracks.count <= 1)

                Button("Select None") {
                    job.selectedTrackIDs = []
                }
                .disabled(job.selectedTracks.isEmpty)

                Button("Auto-Select by Language") {
                    job.selectDefaultTracks()
                }
                .help("Tick every track whose language matches your language preference.")
                .disabled(job.tracks.isEmpty)

                Spacer()

                Text(selectionSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            DisclosureGroup("OCR Options", isExpanded: $showAdvanced) {
                Form {
                    TextField("Languages", text: $job.options.languages, prompt: Text("en"))
                        .help("ISO 639 codes, comma-separated — for example “en,jpn”.")

                    Toggle("Invert images before OCR", isOn: $job.options.invert)
                    Toggle("Disable l→I correction", isOn: $job.options.disableICorrection)

                    TextField("Custom words", text: Binding(
                        get: { job.options.customWords ?? "" },
                        set: { job.options.customWords = $0.isEmpty ? nil : $0 }
                    ), prompt: Text("Optional"))
                    .help("Words the recognizer should prefer, comma-separated.")
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .padding(.top, 4)
            }

            HStack {
                Button("Choose Different File…") { job.reset() }
                Spacer()
                Button(runButtonLabel) { job.startOCR() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(job.selectedTracks.isEmpty)
            }
        }
    }

    private var trackList: some View {
        List {
            if filteredTracks.isEmpty {
                emptyFilterState
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filteredTracks) { track in
                    TrackCheckRow(
                        track: track,
                        isOn: Binding(
                            get: { job.selectedTrackIDs.contains(track.id) },
                            set: { isOn in
                                if isOn { job.selectedTrackIDs.insert(track.id) }
                                else { job.selectedTrackIDs.remove(track.id) }
                            }
                        )
                    )
                }
            }
        }
        // Plain inset: alternating backgrounds paint empty striped rows below
        // the content, which reads as unfinished in a short list.
        .listStyle(.inset)
        .frame(minHeight: 140)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator)
        }
        .accessibilityLabel("Subtitle tracks")
    }

    private var runButtonLabel: String {
        let n = job.selectedTracks.count
        return n <= 1 ? "Run OCR" : "Run OCR on \(n) Tracks"
    }

    private var filteredTracks: [Track] {
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return job.tracks }
        return job.tracks.filter { track in
            track.displayTitle.lowercased().contains(q)
                || track.displaySubtitle.lowercased().contains(q)
                || (track.language?.lowercased().contains(q) ?? false)
                || (track.name?.lowercased().contains(q) ?? false)
        }
    }

    private var selectionSummary: String {
        let selected = job.selectedTracks.count
        let total = job.tracks.count
        let visible = filteredTracks.count
        if filterQuery.isEmpty || visible == total {
            return "\(selected) of \(total) selected"
        }
        return "\(selected) of \(total) selected — \(visible) shown"
    }

    private var trackFilterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Filter tracks", text: $filterQuery,
                      prompt: Text("Filter by language or name"))
                .textFieldStyle(.plain)
                .focused($filterFocused)

            if !filterQuery.isEmpty {
                Button {
                    filterQuery = ""
                    filterFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var emptyFilterState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No tracks match “\(filterQuery)”")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Clear Filter") { filterQuery = "" }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct TrackCheckRow: View {
    let track: Track
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                // No leading glyph here: it centred on the two-line label while
                // the checkbox aligned to the title, which read as misaligned.
                // "Forced" and "Default" are already carried by the badges.
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.displayTitle)
                    Text(track.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if track.isDefault { Badge("Default") }
                if track.isForced { Badge("Forced") }
                if let lang = track.languageBadge { Badge(lang, monospaced: true) }
            }
            .padding(.vertical, 3)
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel(track.displayTitle)
        .accessibilityValue(track.displaySubtitle)
    }
}

private struct Badge: View {
    let text: String
    let monospaced: Bool

    init(_ text: String, monospaced: Bool = false) {
        self.text = text
        self.monospaced = monospaced
    }

    var body: some View {
        Text(text)
            .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

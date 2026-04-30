import SwiftUI

struct TracksView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var showAdvanced = false
    @State private var filterQuery = ""
    @FocusState private var filterFocused: Bool

    var body: some View {
        @Bindable var job = job

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Choose subtitle tracks").font(.title2).bold()
                    if let url = job.input {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                Button("Cancel") { job.reset() }
            }

            if job.tracks.count > 6 {
                trackFilterField
            }

            HStack(spacing: 16) {
                Button("Select all\(filterQuery.isEmpty ? "" : " visible")") {
                    let visibleIDs = filteredTracks.map(\.id)
                    job.selectedTrackIDs.formUnion(visibleIDs)
                }
                .disabled(filteredTracks.count <= 1)
                Button("Select none") {
                    job.selectedTrackIDs = []
                }
                .disabled(job.selectedTracks.isEmpty)
                Button("Auto-select by language") {
                    job.selectDefaultTracks()
                }
                .help("Tick all tracks whose language matches your language preference.")
                .disabled(job.tracks.isEmpty)
                Spacer()
                Text(selectionSummary)
                    .foregroundStyle(.secondary).font(.caption)
            }

            ScrollView {
                VStack(spacing: 4) {
                    if filteredTracks.isEmpty {
                        emptyFilterState
                    } else {
                        ForEach(filteredTracks) { track in
                            TrackCheckRow(
                                track: track,
                                isOn: Binding(
                                    get: { job.selectedTrackIDs.contains(track.id) },
                                    set: { newValue in
                                        if newValue { job.selectedTrackIDs.insert(track.id) }
                                        else        { job.selectedTrackIDs.remove(track.id) }
                                    }
                                )
                            )
                        }
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 280)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            DisclosureGroup("OCR options", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Languages")
                        TextField("en", text: $job.options.languages)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Text("ISO 639-1, comma-separated").foregroundStyle(.secondary).font(.caption)
                    }
                    Toggle("Invert images before OCR", isOn: $job.options.invert)
                    Toggle("Disable l→I correction", isOn: $job.options.disableICorrection)
                    HStack {
                        Text("Custom words")
                        TextField("optional", text: Binding(
                            get: { job.options.customWords ?? "" },
                            set: { job.options.customWords = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 6)
            }

            HStack {
                Spacer()
                Button(runButtonLabel) { job.startOCR() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(job.selectedTracks.isEmpty)
            }
        }
    }

    private var runButtonLabel: String {
        let n = job.selectedTracks.count
        if n <= 1 { return "Run OCR" }
        return "Run OCR (\(n) tracks)"
    }

    private var filteredTracks: [Track] {
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return job.tracks }
        return job.tracks.filter { track in
            track.displayTitle.lowercased().contains(q) ||
            track.displaySubtitle.lowercased().contains(q) ||
            (track.language?.lowercased().contains(q) ?? false) ||
            (track.name?.lowercased().contains(q) ?? false)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter by language or name (e.g. \"sdh\", \"jpn\", \"commentary\")",
                      text: $filterQuery)
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
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyFilterState: some View {
        VStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No tracks match \u{201C}\(filterQuery)\u{201D}")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Clear filter") { filterQuery = "" }
                .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct TrackCheckRow: View {
    let track: Track
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack {
                Image(systemName: track.isForced ? "captions.bubble.fill" : "captions.bubble")
                    .foregroundStyle(track.isForced ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayTitle)
                    Text(track.displaySubtitle)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
                if track.isDefault {
                    Badge("Default")
                }
                if track.isForced {
                    Badge("Forced")
                }
                if let lang = track.languageBadge {
                    Badge(lang, monospaced: true)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 4).padding(.horizontal, 10)
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
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.16), in: Capsule())
    }
}

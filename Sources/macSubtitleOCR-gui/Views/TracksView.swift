import SwiftUI

struct TracksView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var showAdvanced = false

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

            HStack(spacing: 16) {
                Button("Select all") {
                    job.selectedTracks = Set(job.tracks)
                }
                .disabled(job.tracks.count <= 1)
                Button("Select none") {
                    job.selectedTracks = []
                }
                .disabled(job.selectedTracks.isEmpty)
                Spacer()
                Text("\(job.selectedTracks.count) of \(job.tracks.count) selected")
                    .foregroundStyle(.secondary).font(.caption)
            }

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(job.tracks) { track in
                        TrackCheckRow(
                            track: track,
                            isOn: Binding(
                                get: { job.selectedTracks.contains(track) },
                                set: { newValue in
                                    if newValue { job.selectedTracks.insert(track) }
                                    else        { job.selectedTracks.remove(track) }
                                }
                            )
                        )
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
                Button(runButtonLabel) { startRun() }
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

    private func startRun() {
        Task { await OCRPipeline.run(job: job) }
    }
}

private struct TrackCheckRow: View {
    let track: Track
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack {
                Image(systemName: "captions.bubble").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Track \(track.id) — \(track.codec.displayName)")
                    if let name = track.name, !name.isEmpty {
                        Text(name).foregroundStyle(.secondary).font(.caption)
                    }
                }
                Spacer()
                if let lang = track.language {
                    Text(lang.uppercased())
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 4).padding(.horizontal, 10)
    }
}

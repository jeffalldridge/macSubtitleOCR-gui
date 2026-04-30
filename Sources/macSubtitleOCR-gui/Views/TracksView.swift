// Sources/macSubtitleOCR-gui/Views/TracksView.swift
import SwiftUI

struct TracksView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var showAdvanced = false

    var body: some View {
        @Bindable var job = job

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Choose a subtitle track").font(.title2).bold()
                    if let url = job.input {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                Button("Cancel") { job.reset() }
            }

            if job.tracks.count > 1 {
                List(selection: $job.selectedTrack) {
                    ForEach(job.tracks) { track in
                        TrackRow(track: track)
                            .tag(Optional(track))
                    }
                }
                .frame(minHeight: 160)
            } else if let only = job.tracks.first {
                TrackRow(track: only)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .onAppear { job.selectedTrack = only }
            }

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
                Button("Run OCR") { startRun() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(job.selectedTrack == nil)
            }
        }
    }

    private func startRun() {
        Task { await OCRPipeline.run(job: job) }
    }
}

private struct TrackRow: View {
    let track: Track
    var body: some View {
        HStack {
            Image(systemName: "captions.bubble").foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text("Track \(track.id) — \(track.codec.displayName)").font(.body)
                if let name = track.name, !name.isEmpty {
                    Text(name).foregroundStyle(.secondary).font(.caption)
                }
            }
            Spacer()
            if let lang = track.language {
                Text(lang.uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }
}

import AppKit
import SwiftUI

/// The detail column: a track, a file, or nothing.
struct DetailView: View {
    @Environment(ConversionQueue.self) private var queue

    var body: some View {
        if let track = queue.selectedTrack, let file = queue.file(for: track) {
            TrackDetailView(track: track, file: file)
                .id(track.id)
        } else if let file = queue.selectedFile {
            FileDetailView(file: file)
                .id(file.id)
        } else {
            ContentUnavailableView("Select a file or track", systemImage: "sidebar.left",
                                   description: Text("Tick the tracks you want, then click Recognize."))
                .navigationTitle("macSubtitleOCR")
        }
    }
}

struct FileDetailView: View {
    @Environment(ConversionQueue.self) private var queue
    let file: QueueFile

    var body: some View {
        Form {
            Section("File") {
                LabeledContent("Name", value: file.displayName)
                LabeledContent("Location") {
                    HStack {
                        Text(file.url.deletingLastPathComponent().path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        }
                        .controlSize(.small)
                    }
                }
                if let size = file.fileSize {
                    LabeledContent("Size", value: Formatters.fileSize(size))
                }
                if let duration = file.info?.duration {
                    LabeledContent("Duration", value: Formatters.duration(duration))
                }
                if let title = file.info?.title, !title.isEmpty {
                    LabeledContent("Title", value: title)
                }
            }

            Section {
                switch file.state {
                case .probing:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Reading tracks…").foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                case .ready(let info):
                    if file.tracks.isEmpty {
                        Text("This file has no PGS or VobSub subtitle tracks.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(file.tracks) { track in
                        TrackSummaryRow(track: track)
                    }
                    if !info.otherSubtitleCodecs.isEmpty {
                        Text(otherTracksNote(info.otherSubtitleCodecs))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Subtitle Tracks")
            } footer: {
                if !file.tracks.isEmpty {
                    Text("Tick the tracks to recognize. Each one becomes its own .srt file next to the source, named after its language and track name.")
                }
            }

            if !file.tracks.isEmpty {
                Section {
                    HStack {
                        Button("Include All") { queue.includeAll(in: file) }
                        Button("Include None") { queue.includeNone(in: file) }
                        Spacer()
                        Button(runLabel) { queue.run() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!queue.canRun || file.includedTracks.isEmpty)
                    }
                    .disabled(queue.isRunning)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(file.displayName)
        .navigationSubtitle(file.summary)
    }

    private var runLabel: String {
        let count = file.includedTracks.count
        return count == 1 ? "Recognize 1 Track" : "Recognize \(count) Tracks"
    }

    private func otherTracksNote(_ codecs: [String]) -> String {
        let count = codecs.count
        let kinds = Set(codecs.map { codec -> String in
            if codec.hasPrefix("S_TEXT") { return "text" }
            if codec == "S_DVBSUB" { return "DVB bitmap" }
            return codec
        }).sorted().joined(separator: ", ")
        return "\(count) other subtitle track\(count == 1 ? "" : "s") (\(kinds)) \(count == 1 ? "is" : "are") not bitmap subtitles and \(count == 1 ? "does" : "do") not need recognition."
    }
}

private struct TrackSummaryRow: View {
    @Bindable var track: QueueTrack
    @Environment(ConversionQueue.self) private var queue

    var body: some View {
        Toggle(isOn: $track.isIncluded) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                    Text(track.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if track.info.isDefault { Badge(text: "Default") }
                if track.info.isForced { Badge(text: "Forced", tint: .orange) }
                TrackStatusView(track: track)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(queue.isRunning)
    }
}

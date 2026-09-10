import AppKit
import SwiftUI

/// The pane below the queue: a track, a file, or an explanation of what to do
/// next.
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
            ContentUnavailableView("Select a track to review it",
                                   systemImage: "list.bullet.rectangle",
                                   description: Text("Tick the tracks you want in the list above, then click Recognize."))
                .navigationTitle("macSubtitleOCR")
        }
    }
}

/// A file's own details. Its tracks are in the queue above, with their
/// checkboxes, so they are not repeated here.
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
                            .help(file.url.path(percentEncoded: false))
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

            Section("Subtitle Tracks") {
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
                    } else {
                        LabeledContent("Bitmap tracks", value: trackSummary)
                        Text("Each included track becomes its own .srt file next to the source, named after its language and track name.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if !info.otherSubtitleCodecs.isEmpty {
                        Text(otherTracksNote(info.otherSubtitleCodecs))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
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

    private var trackSummary: String {
        let included = file.includedTracks.count
        let total = file.tracks.count
        if included == total { return total == 1 ? "1, included" : "\(total), all included" }
        return "\(included) of \(total) included"
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
        let noun = count == 1 ? "track" : "tracks"
        let verb = count == 1 ? "is" : "are"
        let need = count == 1 ? "does" : "do"
        return "\(count) other subtitle \(noun) (\(kinds)) \(verb) not bitmap subtitles and \(need) not need recognition."
    }
}

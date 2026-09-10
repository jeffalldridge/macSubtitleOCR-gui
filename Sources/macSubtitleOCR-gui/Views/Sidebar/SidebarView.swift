import AppKit
import SwiftUI

/// Files and their bitmap subtitle tracks as an outline.
struct SidebarView: View {
    @Environment(ConversionQueue.self) private var queue
    @State private var collapsed: Set<UUID> = []

    var body: some View {
        @Bindable var queue = queue

        List(selection: $queue.selection) {
            ForEach(queue.files) { file in
                DisclosureGroup(isExpanded: expansionBinding(for: file)) {
                    ForEach(file.tracks) { track in
                        TrackRow(track: track)
                            .tag(SidebarSelection.track(track.id))
                            .disabled(queue.isRunning && !track.status.isRunning && track.status != .done)
                    }
                } label: {
                    FileRow(file: file)
                }
                .tag(SidebarSelection.file(file.id))
                .contextMenu { fileMenu(file) }
            }
        }
        .listStyle(.sidebar)
        .popoverTip(DropFilesTip(), arrowEdge: .top)
        .accessibilityLabel("Files and subtitle tracks")
    }

    private func expansionBinding(for file: QueueFile) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(file.id) },
            set: { expanded in
                if expanded { collapsed.remove(file.id) } else { collapsed.insert(file.id) }
            }
        )
    }

    @ViewBuilder
    private func fileMenu(_ file: QueueFile) -> some View {
        Button("Include All Tracks") { queue.includeAll(in: file) }
            .disabled(file.tracks.isEmpty || queue.isRunning)
        Button("Include No Tracks") { queue.includeNone(in: file) }
            .disabled(file.tracks.isEmpty || queue.isRunning)
        Divider()
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        }
        Divider()
        Button("Remove from Queue", role: .destructive) { queue.remove(file) }
            .disabled(queue.isRunning)
    }
}

struct FileRow: View {
    let file: QueueFile

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.summary)
                    .font(.caption)
                    .foregroundStyle(isFailed ? .red : .secondary)
                    .lineLimit(2)
            }
        } icon: {
            if file.state == .probing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(isFailed ? .orange : .accentColor)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isFailed: Bool {
        if case .failed = file.state { return true }
        return false
    }

    private var icon: String {
        if isFailed { return "exclamationmark.triangle" }
        return file.source.isContainer ? "film" : "captions.bubble"
    }
}

struct TrackRow: View {
    @Bindable var track: QueueTrack
    @Environment(ConversionQueue.self) private var queue

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $track.isIncluded)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(queue.isRunning)
                .help("Include this track when recognizing")
                .accessibilityLabel("Include \(track.title)")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .lineLimit(1)
                    if track.info.isForced { Badge(text: "Forced", tint: .orange) }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            TrackStatusView(track: track)
        }
        .padding(.vertical, 2)
        .modifier(DraggableOutput(url: track.outputURL))
        .accessibilityElement(children: .combine)
        .accessibilityValue(track.status.label)
    }

    private var detail: String {
        var parts = [track.subtitle]
        if let count = track.cueCount { parts.append("\(count.formatted()) cues") }
        if track.info.isDefault, !track.info.isForced { parts.append("Default") }
        return parts.joined(separator: " · ")
    }
}

/// A finished track can be dragged out of the window as its SRT file.
private struct DraggableOutput: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.draggable(url)
        } else {
            content
        }
    }
}

/// Trailing status: spinner, progress, done check, or a warning.
struct TrackStatusView: View {
    let track: QueueTrack

    var body: some View {
        switch track.status {
        case .idle:
            EmptyView()
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
                .help("Waiting")
        case .extracting, .indexing, .saving:
            ProgressView().controlSize(.small)
                .help(track.status.label)
        case .recognizing(let done, let total):
            HStack(spacing: 6) {
                Text("\(done.formatted()) / \(total.formatted())")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
            .help("Recognizing")
        case .done:
            HStack(spacing: 4) {
                if track.reviewCount > 0 {
                    Text("\(track.reviewCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("\(track.reviewCount) cues to review")
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Done")
                }
            }
        case .failed(let message):
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help(message)
        case .cancelled:
            Image(systemName: "slash.circle")
                .foregroundStyle(.tertiary)
                .help("Cancelled")
        }
    }
}

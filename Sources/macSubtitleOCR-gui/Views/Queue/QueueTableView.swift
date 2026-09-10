import AppKit
import SwiftUI

/// One row of the queue: a file, or one of its subtitle tracks.
///
/// The table is hierarchical, so both kinds share a row type. The identifier
/// is the window's selection type, which is what lets a click in the table and
/// a selection made anywhere else mean the same thing.
enum QueueRow: Identifiable {
    case file(QueueFile)
    case track(QueueTrack)

    var id: SidebarSelection {
        switch self {
        case .file(let file): .file(file.id)
        case .track(let track): .track(track.id)
        }
    }
}

/// The queue: every file and its bitmap subtitle tracks, with what each one
/// is doing right now.
struct QueueTableView: View {
    @Environment(ConversionQueue.self) private var queue
    @State private var collapsed: Set<UUID> = []

    var body: some View {
        @Bindable var queue = queue

        Table(of: QueueRow.self, selection: $queue.selection) {
            TableColumn("") { row in
                includeCell(row)
            }
            .width(QueueTableLayout.includeWidth)

            TableColumn("Name") { row in
                nameCell(row)
            }
            .width(min: QueueTableLayout.nameMinimumWidth, ideal: QueueTableLayout.nameIdealWidth)

            TableColumn("Kind") { row in
                switch row {
                case .file(let file):
                    Text(file.source.isContainer ? "Video" : "Subtitles")
                        .foregroundStyle(.secondary)
                case .track(let track):
                    Text(track.subtitle).foregroundStyle(.secondary)
                }
            }
            .width(min: QueueTableLayout.kindMinimumWidth,
                   ideal: QueueTableLayout.kindIdealWidth,
                   max: QueueTableLayout.kindMaximumWidth)

            TableColumn("Language") { row in
                switch row {
                case .file(let file):
                    Text(file.info?.title ?? "").foregroundStyle(.secondary).lineLimit(1)
                case .track(let track):
                    HStack(spacing: 4) {
                        Text(track.languageName).lineLimit(1)
                        if track.info.isForced { Badge(text: "Forced", tint: .orange) }
                        if track.info.isDefault, !track.info.isForced { Badge(text: "Default") }
                    }
                }
            }
            .width(min: QueueTableLayout.languageMinimumWidth,
                   ideal: QueueTableLayout.languageIdealWidth,
                   max: QueueTableLayout.languageMaximumWidth)

            TableColumn("Cues") { row in
                cueCountCell(row)
            }
            .width(min: QueueTableLayout.cuesMinimumWidth,
                   ideal: QueueTableLayout.cuesIdealWidth,
                   max: QueueTableLayout.cuesMaximumWidth)

            TableColumn("Status") { row in
                switch row {
                case .file(let file): FileStatusCell(file: file)
                case .track(let track): TrackStatusCell(track: track)
                }
            }
            .width(min: QueueTableLayout.statusMinimumWidth,
                   ideal: QueueTableLayout.statusIdealWidth,
                   max: QueueTableLayout.statusMaximumWidth)
        } rows: {
            ForEach(queue.files) { file in
                if file.tracks.isEmpty {
                    TableRow(QueueRow.file(file))
                        .contextMenu { fileMenu(file) }
                } else {
                    DisclosureTableRow(QueueRow.file(file), isExpanded: expansion(of: file)) {
                        ForEach(file.tracks) { track in
                            TableRow(QueueRow.track(track))
                                .contextMenu { trackMenu(track, in: file) }
                                .draggable(dragItem(for: track))
                        }
                    }
                    .contextMenu { fileMenu(file) }
                }
            }
        }
        .tableStyle(.inset)
        .onDeleteCommand(perform: removeSelected)
        .popoverTip(DropFilesTip(), arrowEdge: .top)
        .accessibilityLabel("Queue of files and subtitle tracks")
    }

    // MARK: - Cells

    @ViewBuilder
    private func includeCell(_ row: QueueRow) -> some View {
        switch row {
        case .file(let file):
            if !file.tracks.isEmpty {
                Toggle("", isOn: fileInclusion(file))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(queue.isRunning)
                    .help("Include every track in this file")
                    .accessibilityLabel("Include all tracks in \(file.displayName)")
            }
        case .track(let track):
            TrackIncludeToggle(track: track)
        }
    }

    @ViewBuilder
    private func nameCell(_ row: QueueRow) -> some View {
        switch row {
        case .file(let file):
            Label {
                Text(file.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // The column truncates long film names, so the whole name
                    // has to be available some other way.
                    .help(file.url.path(percentEncoded: false))
            } icon: {
                Image(systemName: fileIcon(file))
                    .foregroundStyle(file.hasFailed ? Color.orange : Color.accentColor)
            }
        case .track(let track):
            Text(track.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(track.title)
        }
    }

    @ViewBuilder
    private func cueCountCell(_ row: QueueRow) -> some View {
        switch row {
        case .file(let file):
            let total = file.tracks.compactMap(\.cueCount).reduce(0, +)
            Text(total > 0 ? total.formatted() : "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .track(let track):
            Text(track.cueCount?.formatted() ?? "—")
                .monospacedDigit()
                .foregroundStyle(track.cueCount == nil ? .tertiary : .secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func fileIcon(_ file: QueueFile) -> String {
        if file.hasFailed { return "exclamationmark.triangle" }
        return file.source.isContainer ? "film" : "captions.bubble"
    }

    /// A finished track can be dragged out of the window as its SRT file; an
    /// unfinished one drags its source, which is at least something to drop.
    private func dragItem(for track: QueueTrack) -> URL {
        track.outputURL ?? queue.file(for: track)?.url ?? URL(fileURLWithPath: "/")
    }

    // MARK: - Bindings

    private func expansion(of file: QueueFile) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(file.id) },
            set: { expanded in
                if expanded { collapsed.remove(file.id) } else { collapsed.insert(file.id) }
            }
        )
    }

    /// Ticking a file ticks all of its tracks; the box shows filled only when
    /// every one of them is ticked.
    private func fileInclusion(_ file: QueueFile) -> Binding<Bool> {
        Binding(
            get: { !file.tracks.isEmpty && file.tracks.allSatisfy(\.isIncluded) },
            set: { include in
                if include { queue.includeAll(in: file) } else { queue.includeNone(in: file) }
            }
        )
    }

    // MARK: - Commands

    private func removeSelected() {
        guard !queue.isRunning else { return }
        switch queue.selection {
        case .file(let id):
            if let file = queue.file(id: id) { queue.remove(file) }
        case .track(let id):
            // A track cannot leave without its file, so this removes nothing
            // and unticks it instead — the reversible reading of "delete".
            queue.track(id: id)?.isIncluded = false
        case nil:
            break
        }
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

    @ViewBuilder
    private func trackMenu(_ track: QueueTrack, in file: QueueFile) -> some View {
        Button(track.isIncluded ? "Don’t Recognize This Track" : "Recognize This Track") {
            track.isIncluded.toggle()
        }
        .disabled(queue.isRunning)
        if let output = track.outputURL {
            Divider()
            Button("Reveal Subtitle File in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([output])
            }
        }
    }
}

/// Split out so ticking one track redraws one row rather than the table.
private struct TrackIncludeToggle: View {
    @Bindable var track: QueueTrack
    @Environment(ConversionQueue.self) private var queue

    var body: some View {
        Toggle("", isOn: $track.isIncluded)
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(queue.isRunning)
            .help("Recognize this track")
            .accessibilityLabel("Recognize \(track.title)")
    }
}

/// What a file is doing: reading its tracks, ready, or unreadable.
struct FileStatusCell: View {
    let file: QueueFile

    var body: some View {
        switch file.state {
        case .probing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .lineLimit(1)
                .foregroundStyle(.orange)
                .help(message)
        case .ready:
            Text(file.summary)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .help(file.summary)
        }
    }
}

/// What a track is doing, as an icon and a word rather than an icon alone.
///
/// Green is reserved for a subtitle file that has been written and needs no
/// attention; orange means there is something to look at; red means it did
/// not happen. Anything still in progress stays uncoloured, so a glance down
/// the column finds the rows that want the user.
struct TrackStatusCell: View {
    let track: QueueTrack

    var body: some View {
        switch track.status {
        case .idle:
            switch track.loadState {
            case .notLoaded:
                Text(track.isIncluded ? "Ready" : "Not included")
                    .foregroundStyle(track.isIncluded ? .secondary : .tertiary)
            case .loading(let fraction):
                progress(fraction, label: "Reading track")
            case .loaded:
                Text("Ready").foregroundStyle(.secondary)
            case .failed(let message):
                label("Unreadable", systemImage: "exclamationmark.triangle.fill",
                      tint: .orange, help: message)
            }
        case .queued:
            label("Waiting", systemImage: "clock", tint: .secondary)
        case .extracting(let fraction):
            progress(fraction, label: "Reading track")
        case .indexing:
            progress(nil, label: "Indexing cues")
        case .recognizing(let done, let total):
            HStack(spacing: 6) {
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("\(done.formatted()) of \(total.formatted())")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .help("Recognizing")
        case .saving:
            progress(nil, label: "Saving")
        case .done:
            if track.reviewCount > 0 {
                label("\(track.reviewCount.formatted()) to review",
                      systemImage: "exclamationmark.triangle.fill", tint: .orange,
                      help: "Vision was unsure about these cues")
            } else {
                label("Done", systemImage: "checkmark.circle.fill", tint: .green,
                      help: track.outputURL?.path(percentEncoded: false))
            }
        case .failed(let message):
            label("Failed", systemImage: "xmark.octagon.fill", tint: .red, help: message)
        case .cancelled:
            label("Cancelled", systemImage: "slash.circle", tint: .secondary)
        }
    }

    private func label(_ text: String, systemImage: String, tint: Color, help: String? = nil) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(tint == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .help(help ?? text)
            .accessibilityLabel(text)
    }

    private func progress(_ fraction: Double?, label text: String) -> some View {
        HStack(spacing: 6) {
            if let fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text).foregroundStyle(.secondary).lineLimit(1)
        }
        .help(text)
        .accessibilityLabel(text)
    }
}

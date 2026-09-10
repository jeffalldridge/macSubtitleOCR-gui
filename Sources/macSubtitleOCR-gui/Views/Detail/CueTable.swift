import SubtitleEngine
import SwiftUI

/// The cue list: thumbnail, timing, editable text, and a review flag.
struct CueTable: View {
    let track: QueueTrack
    let rows: [CueRowModel]
    @Binding var selection: Int?
    let onEdit: (ReviewCue, String) -> Void

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("") { row in
                ReviewFlag(cue: row.cue)
            }
            .width(CueTableLayout.flagWidth)

            TableColumn("#") { row in
                Text("\(row.info.index + 1)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: CueTableLayout.numberMinimumWidth,
                   ideal: CueTableLayout.numberIdealWidth,
                   max: CueTableLayout.numberMaximumWidth)

            TableColumn("Image") { row in
                CueThumbnail(track: track, index: row.info.index)
                    .frame(height: CueTableLayout.thumbnailHeight)
            }
            .width(min: CueTableLayout.imageMinimumWidth,
                   ideal: CueTableLayout.imageIdealWidth,
                   max: CueTableLayout.imageMaximumWidth)

            TableColumn("Time") { row in
                Text(timeLabel(row))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: CueTableLayout.timeMinimumWidth,
                   ideal: CueTableLayout.timeIdealWidth,
                   max: CueTableLayout.timeMaximumWidth)

            TableColumn(track.hasResults ? "Text · Edits save to SRT" : "Text") { row in
                if let cue = row.cue {
                    CueTextCell(cue: cue, onEdit: onEdit)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(min: CueTableLayout.textMinimumWidth)
        }
        .tableStyle(.inset)
        .accessibilityLabel("Cues")
    }

    private func timeLabel(_ row: CueRowModel) -> String {
        if let cue = row.cue { return Formatters.range(cue.start, cue.end) }
        if let end = row.info.end { return Formatters.range(row.info.start, end) }
        return Formatters.clock(row.info.start)
    }
}

private struct ReviewFlag: View {
    let cue: ReviewCue?

    var body: some View {
        if let cue {
            if cue.needsReview {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(cue.hadBitmap && cue.text.isEmpty ? "Nothing was recognized"
                          : "Low confidence (\(Formatters.percent(Double(cue.confidence))))")
                    .accessibilityLabel("Needs review")
            } else if cue.isEdited {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.blue)
                    .help("Edited")
                    .accessibilityLabel("Edited")
            } else if cue.isMarkedReviewed {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .help("Reviewed")
            }
        }
    }
}

/// Editable, multi-line cue text.
struct CueTextCell: View {
    @Bindable var cue: ReviewCue
    let onEdit: (ReviewCue, String) -> Void
    @State private var draft = ""
    @State private var editingFrom: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .focused($focused)
            .onAppear { draft = cue.text }
            .onChange(of: cue.text) { _, value in
                if !focused { draft = value }
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    editingFrom = cue.text
                } else {
                    commit()
                }
            }
            .onSubmit { commit() }
            .contextMenu {
                if cue.flagged, !cue.isEdited {
                    Button(cue.isMarkedReviewed ? "Mark as Needs Review" : "Mark as Reviewed") {
                        cue.isMarkedReviewed.toggle()
                    }
                }
                if cue.isEdited {
                    Button("Revert to Recognized Text") {
                        let previous = cue.text
                        cue.revert()
                        draft = cue.text
                        // Same path as a normal edit: undo, and a write to disk.
                        onEdit(cue, previous)
                    }
                }
            }
            .accessibilityLabel("Cue text")
    }

    private func commit() {
        let previous = editingFrom ?? cue.text
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { editingFrom = nil }
        guard trimmed != cue.text else { return }
        cue.text = trimmed
        draft = trimmed
        onEdit(cue, previous)
        editingFrom = nil
    }
}

/// An asynchronously decoded thumbnail of a cue's bitmap.
struct CueThumbnail: View {
    let track: QueueTrack
    let index: Int
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Color.clear
            }
        }
        .padding(.vertical, 3)
        .task(id: "\(track.id)/\(index)") {
            image = nil
            let loaded = await CueImageCache.shared.image(for: track, index: index)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

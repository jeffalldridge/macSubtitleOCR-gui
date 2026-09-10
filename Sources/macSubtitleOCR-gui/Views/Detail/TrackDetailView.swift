import AppKit
import SubtitleEngine
import SwiftUI

/// A track: its cues as thumbnails before recognition, and as an editable
/// review list afterwards.
struct TrackDetailView: View {
    @Environment(ConversionQueue.self) private var queue
    @Environment(AppUIState.self) private var ui
    @Environment(\.undoManager) private var undoManager

    let track: QueueTrack
    let file: QueueFile

    @State private var selectedCue: Int?
    @State private var search = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        @Bindable var ui = ui

        VStack(spacing: 0) {
            header
            Divider()
            CuePreviewView(track: track, cueIndex: selectedCue)
                .frame(height: CuePreviewLayout.height)
            Divider()
            content
        }
        .navigationTitle(track.title)
        .navigationSubtitle(subtitle)
        .task(id: track.id) {
            queue.loadStreamIfNeeded(for: track)
        }
        .onDisappear {
            // Switching tracks must not outrun the debounced save.
            saveTask?.cancel()
            if track.hasUnsavedEdits { queue.saveEdits(for: track) }
        }
        .onChange(of: rows.map(\.id)) { _, ids in
            if let selectedCue, !ids.contains(selectedCue) { self.selectedCue = ids.first }
            if selectedCue == nil { selectedCue = ids.first }
        }
    }

    // MARK: - Header

    private var header: some View {
        @Bindable var ui = ui
        return HStack(alignment: .firstTextBaseline, spacing: DetailPaneMetrics.horizontalPadding * 0.75) {
            VStack(alignment: .leading, spacing: DetailPaneMetrics.stackSpacing) {
                HStack(spacing: DetailPaneMetrics.titleSpacing) {
                    Text(track.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(track.title)
                    if track.info.isDefault { Badge(text: "Default") }
                    if track.info.isForced { Badge(text: "Forced", tint: .orange) }
                }
                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(statusLine)
                if !track.issues.isEmpty {
                    DisclosureGroup {
                        ForEach(track.issues, id: \.self) { issue in
                            Text(issue).font(.caption).foregroundStyle(.secondary)
                        }
                    } label: {
                        Label("\(track.issues.count) note\(track.issues.count == 1 ? "" : "s")", systemImage: "info.circle")
                            .font(.caption)
                    }
                }
            }
            Spacer(minLength: DetailPaneMetrics.horizontalPadding)

            HStack(spacing: DetailPaneMetrics.titleSpacing) {
                CueSearchField(text: $search)
                    .disabled(track.stream == nil)

                Toggle(isOn: $ui.showNeedsReviewOnly) {
                    Label("Needs Review", systemImage: "exclamationmark.triangle")
                        .labelStyle(.iconOnly)
                }
                .toggleStyle(.button)
                .help("Show only cues that need a look (⌥⌘E)")
                .disabled(!track.hasResults)

                if let output = track.outputURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .help(output.path(percentEncoded: false))
                }
                if track.hasResults {
                    TrackActionsMenu(track: track, file: file)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, DetailPaneMetrics.horizontalPadding)
        .padding(.vertical, DetailPaneMetrics.verticalPadding)
    }

    private var subtitle: String {
        var parts = [file.displayName, track.subtitle]
        if let count = track.cueCount { parts.append("\(count.formatted()) cues") }
        return parts.joined(separator: " · ")
    }

    private var statusLine: String {
        switch track.status {
        case .done:
            var parts: [String] = ["\(track.cues.count.formatted()) cues recognized"]
            let review = track.reviewCount
            parts.append(review == 0 ? "nothing flagged" : "\(review) to review")
            if track.editedCount > 0 { parts.append("\(track.editedCount) edited") }
            return parts.joined(separator: " · ")
        case .failed(let message):
            return message
        case .idle, .queued, .cancelled:
            switch track.loadState {
            case .notLoaded: return "Preparing preview…"
            case .loading(let p): return "Reading track… \(Formatters.percent(p))"
            case .loaded: return "\(track.cueCount?.formatted() ?? "0") cues · not recognized yet"
            case .failed(let message): return message
            }
        default:
            return ConversionQueue.activityLabel(for: track)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch track.loadState {
        case .notLoaded, .loading:
            VStack(spacing: 10) {
                ProgressView(value: loadFraction)
                    .frame(maxWidth: 260)
                Text(track.loadState == .notLoaded ? "Preparing…" : "Reading the subtitle track from the file…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Couldn’t read this track", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .loaded:
            if rows.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                CueTable(track: track, rows: rows, selection: $selectedCue, onEdit: cueEdited)
                    .popoverTip(EditCueTip(), arrowEdge: .top)
            }
        }
    }

    private var loadFraction: Double? {
        if case .loading(let p) = track.loadState { return p }
        return nil
    }

    private var rows: [CueRowModel] {
        guard let stream = track.stream else { return [] }
        let cuesByIndex = Dictionary(uniqueKeysWithValues: track.cues.map { ($0.index, $0) })
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return stream.cues.compactMap { info in
            let cue = cuesByIndex[info.index]
            if ui.showNeedsReviewOnly, track.hasResults, !(cue?.needsReview ?? false) { return nil }
            if !query.isEmpty {
                let haystack = (cue?.text ?? "").lowercased() + " " + Formatters.clock(info.start)
                if !haystack.contains(query) { return nil }
            }
            return CueRowModel(info: info, cue: cue)
        }
    }

    // MARK: - Editing

    private func cueEdited(_ cue: ReviewCue, previous: String) {
        guard cue.text != previous else { return }
        register(cue, from: previous, to: cue.text)
        scheduleSave()
    }

    /// Register an undo that itself registers a redo, and so on. Without the
    /// recursion the chain stops after one round trip: AppKit routes a
    /// registration made during a redo back onto the undo stack, so each step
    /// has to register the next.
    private func register(_ cue: ReviewCue, from previous: String, to current: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: cue) { target in
            target.text = previous
            Task { @MainActor in
                register(target, from: current, to: previous)
                scheduleSave()
            }
        }
        undoManager.setActionName("Edit Cue")
    }

    private func scheduleSave() {
        track.hasUnsavedEdits = true
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            queue.saveEdits(for: track)
        }
    }
}

/// The cue search field.
///
/// It sits in the detail header rather than the window toolbar: the toolbar
/// belongs to the queue above, and a field that filters the list directly
/// beneath it is easier to connect to what it does.
struct CueSearchField: View {
    @Binding var text: String
    @Environment(AppUIState.self) private var ui
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search cues", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .frame(width: CueSearchLayout.width)
            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear the search")
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: ui.focusSearchRequests) { _, _ in focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search cues")
    }
}

struct CueRowModel: Identifiable {
    let info: CueInfo
    let cue: ReviewCue?
    var id: Int { info.index }
}

/// Reveal, translate, and clean-up actions for a finished track.
struct TrackActionsMenu: View {
    @Environment(ConversionQueue.self) private var queue
    let track: QueueTrack
    let file: QueueFile
    @State private var showTranslate = false
    @State private var showCleanup = false

    var body: some View {
        Menu {
            Button("Translate…", systemImage: "character.book.closed") { showTranslate = true }
            if #available(macOS 26, *), CleanupAssistant.isAvailable {
                Button("Clean Up with Apple Intelligence…", systemImage: "sparkles") { showCleanup = true }
                    .disabled(track.reviewCount == 0)
            }
            Divider()
            Button("Revert All Edits") {
                for cue in track.cues { cue.revert() }
                // The table shows the recognized text again; the file has to
                // agree, or the two diverge with nothing on screen saying so.
                queue.saveEdits(for: track)
            }
            .disabled(track.editedCount == 0)
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .help("Translate, clean up, or revert edits")
        .sheet(isPresented: $showTranslate) {
            TranslationExportView(track: track, file: file)
        }
        .sheet(isPresented: $showCleanup) {
            if #available(macOS 26, *) {
                CleanupSuggestionsView(track: track)
            }
        }
    }
}

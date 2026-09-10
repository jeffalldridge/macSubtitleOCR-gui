import SwiftUI

/// The main window: the queue above, what the selection calls for below, and
/// a status bar that is always there.
///
/// The queue used to be a sidebar, which cost the cue review a permanent
/// quarter of the window's width. Reviewing cues means reading a subtitle
/// image beside its text, and that wants every pixel across. Stacking the two
/// gives the review the full width and lets the user set the split.
struct MainWindow: View {
    static let windowID = "main"

    @Environment(ConversionQueue.self) private var queue
    @Environment(AppUIState.self) private var ui
    @Environment(AppSettings.self) private var settings
    @Environment(UpdateChecker.self) private var updates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var ui = ui

        VStack(spacing: 0) {
            if queue.isEmpty {
                EmptyQueueView(isTargeted: isDropTargeted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VSplitView {
                    QueueTableView()
                        .frame(minHeight: MainWindowLayout.queueMinimumHeight,
                               idealHeight: MainWindowLayout.queueIdealHeight)
                    DetailView()
                        .frame(minHeight: MainWindowLayout.detailMinimumHeight,
                               idealHeight: MainWindowLayout.detailIdealHeight,
                               maxHeight: .infinity)
                }
            }
            QueueStatusBar()
        }
        .frame(minWidth: MainWindowLayout.minimumWidth,
               idealWidth: MainWindowLayout.idealWidth,
               minHeight: MainWindowLayout.minimumHeight,
               idealHeight: MainWindowLayout.idealHeight)
        .dropDestination(for: URL.self) { urls, _ in
            let expanded = urls.flatMap(FileImport.expand)
            guard !expanded.isEmpty else { return false }
            queue.add(urls: expanded)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted, !queue.isEmpty {
                RoundedRectangle(cornerRadius: EmptyQueueLayout.cornerRadius)
                    .strokeBorder(Color.accentColor, lineWidth: EmptyQueueLayout.dropBorderWidth)
                    .padding(EmptyQueueLayout.dropBorderWidth)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDropTargeted)
        .toolbar { toolbar }
        .inspector(isPresented: $ui.isInspectorPresented) {
            InspectorView()
                .inspectorColumnWidth(min: MainWindowLayout.inspectorMinimumWidth,
                                      ideal: MainWindowLayout.inspectorIdealWidth,
                                      max: MainWindowLayout.inspectorMaximumWidth)
        }
        .sensoryFeedback(.success, trigger: queue.finishedRunCount)
        .onChange(of: queue.finishedRunCount) { _, _ in
            runDidFinish()
        }
        .onChange(of: queue.overallProgress) { _, value in
            if queue.isRunning { DockProgress.update(value) } else { DockProgress.hide() }
        }
        .onChange(of: queue.isRunning) { _, running in
            if !running { DockProgress.hide() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                FileImport.presentOpenPanel(into: queue)
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .help("Add video or subtitle files (⌘O)")
            .disabled(queue.isRunning)

            Button {
                removeSelectedFile()
            } label: {
                Label("Remove", systemImage: "minus")
            }
            .help("Remove the selected file from the queue")
            .disabled(queue.isRunning || selectedFileForRemoval == nil)
        }

        ToolbarItem(placement: .primaryAction) {
            if queue.isRunning {
                Button {
                    queue.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .help("Stop recognizing (⌘.)")
            } else {
                Button {
                    queue.run()
                } label: {
                    Label(recognizeLabel, systemImage: "text.viewfinder")
                }
                .help("Recognize the included tracks (⌘R)")
                .disabled(!queue.canRun)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                ui.isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide recognition options (⌥⌘I)")
        }
    }

    /// The file a Remove would act on: the selected one, or the one holding
    /// the selected track.
    private var selectedFileForRemoval: QueueFile? {
        if let file = queue.selectedFile { return file }
        if let track = queue.selectedTrack { return queue.file(for: track) }
        return nil
    }

    private func removeSelectedFile() {
        guard let file = selectedFileForRemoval else { return }
        queue.remove(file)
    }

    private var recognizeLabel: String {
        let count = queue.includedTracks.count
        return count > 1 ? "Recognize \(count) Tracks" : "Recognize"
    }

    private func runDidFinish() {
        guard case .finished(let summary) = queue.runState else { return }
        Notifier.runFinished(summary, settings: settings)
        DockProgress.hide()
        guard settings.openReviewWhenDone else { return }
        let done = queue.completedTracks
        if let flagged = done.first(where: { $0.reviewCount > 0 }) {
            queue.selection = .track(flagged.id)
            if flagged.reviewCount > 0 { ui.showNeedsReviewOnly = true }
        } else if let first = done.first {
            queue.selection = .track(first.id)
        }
    }
}

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
        // Everything the toolbar needs is read here, in the window's own body,
        // and handed over as values. Toolbar items are hosted separately from
        // the window's view tree, and an `@Environment` read that happens
        // inside one of those traps if the object did not travel with it.
        @Bindable var ui = ui
        let queue = self.queue
        let removable = selectedFileForRemoval

        return VStack(spacing: 0) {
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
        .toolbar { toolbar(queue: queue, ui: self.ui, removable: removable) }
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
    private func toolbar(queue: ConversionQueue,
                         ui: AppUIState,
                         removable: QueueFile?) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                FileImport.presentOpenPanel(into: queue)
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .help("Add video or subtitle files (⌘O)")
            .disabled(queue.isRunning)

            Button {
                if let removable { queue.remove(removable) }
            } label: {
                Label("Remove", systemImage: "minus")
            }
            .help("Remove the selected file from the queue")
            .disabled(queue.isRunning || removable == nil)
        }

        ToolbarItem {
            OutputDestinationMenu(settings: settings, isRunning: queue.isRunning)
        }

        // The one button that starts the work, top right, filled in and
        // unmistakable. It becomes Stop in the same place, so the eye never
        // has to go looking for the control that ends what it started.
        ToolbarItem(placement: .primaryAction) {
            if queue.isRunning {
                Button("Stop", systemImage: "stop.fill", role: .destructive) {
                    queue.cancel()
                }
                .buttonStyle(.bordered)
                .help("Stop recognizing and leave the rest of the queue (⌘.)")
            } else {
                Button(recognizeLabel(queue), systemImage: "play.fill") {
                    startRun(queue)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!queue.canRun)
                .help(runHelp(queue))
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

    /// A disabled button that will not say why is a dead end. This says what
    /// is missing instead.
    private func runHelp(_ queue: ConversionQueue) -> String {
        if queue.files.contains(where: { $0.state == .probing }) {
            return "Still reading the files you added"
        }
        if queue.includedTracks.isEmpty {
            return "Tick at least one track in the list above"
        }
        return "Recognize every ticked track and write its subtitle file (⌘R)"
    }

    /// Ask for the folder first when that is what the user asked for. The
    /// panel has to come up before the run starts, not part-way through it.
    private func startRun(_ queue: ConversionQueue) {
        if settings.outputDestination.asksBeforeRunning {
            guard let folder = FileImport.presentFolderPanel() else { return }
            queue.runOptions.outputFolder = folder
        } else {
            queue.runOptions.outputFolder = settings.outputDestination.resolvedFolder
        }
        queue.run()
    }

    /// "Make 3 Subtitle Files" says what lands on disk. "Recognize" describes
    /// what the computer does, which is not what the user came for.
    private func recognizeLabel(_ queue: ConversionQueue) -> String {
        let count = queue.includedTracks.count
        switch count {
        case 0, 1: return "Make Subtitles"
        default: return "Make \(count) Subtitle Files"
        }
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

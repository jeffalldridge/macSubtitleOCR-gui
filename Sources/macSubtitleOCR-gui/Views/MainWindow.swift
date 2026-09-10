import SwiftUI

struct MainWindow: View {
    static let windowID = "main"

    @Environment(ConversionQueue.self) private var queue
    @Environment(AppUIState.self) private var ui
    @Environment(AppSettings.self) private var settings
    @Environment(UpdateChecker.self) private var updates

    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var ui = ui

        Group {
            if queue.isEmpty {
                EmptyStateView(isTargeted: isDropTargeted)
            } else {
                splitView
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .dropDestination(for: URL.self) { urls, _ in
            let expanded = urls.flatMap(FileImport.expand)
            guard !expanded.isEmpty else { return false }
            queue.add(urls: expanded)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .toolbar { toolbar }
        .inspector(isPresented: $ui.isInspectorPresented) {
            InspectorView()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsStatusBar {
                StatusBarView()
            }
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

    private var splitView: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 310, max: 460)
        } detail: {
            DetailView()
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                FileImport.presentOpenPanel(into: queue)
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .help("Add video or subtitle files (⌘O)")
            .disabled(queue.isRunning)
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

    private var recognizeLabel: String {
        let count = queue.includedTracks.count
        return count > 1 ? "Recognize \(count) Tracks" : "Recognize"
    }

    private var showsStatusBar: Bool {
        if queue.isRunning { return true }
        if case .finished = queue.runState { return true }
        return updates.available != nil
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

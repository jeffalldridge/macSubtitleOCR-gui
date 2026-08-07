import SwiftUI

struct AppView: View {
    @Environment(SubtitleJob.self) private var job

    var body: some View {
        Group {
            switch job.phase {
            case .idle, .probing:
                DropView()
            case .tracks:
                TracksView()
            case .running:
                RunView()
            case .done, .failed:
                DoneView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scenePadding()
        .frame(minWidth: 560, minHeight: 440)
        // The title bar carries the app and document identity, so the content
        // area doesn't repeat it (HIG: don't duplicate the window title).
        .navigationTitle(job.input?.lastPathComponent ?? "macSubtitleOCR")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    FileImport.presentOpenPanel(into: job)
                } label: {
                    Label("Open…", systemImage: "folder")
                }
                .help("Open a video or subtitle file")
                .disabled(!FileImport.canImport(into: job))
            }
        }
    }

    /// Secondary line in the title bar: where we are, in the file's terms.
    private var subtitle: String {
        switch job.phase {
        case .idle:
            ""
        case .probing:
            "Reading subtitle tracks…"
        case .tracks:
            job.tracks.count == 1
                ? "1 subtitle track"
                : "\(job.tracks.count) subtitle tracks"
        case .running:
            "Converting…"
        case .done(let outputs):
            outputs.count == 1 ? "1 file saved" : "\(outputs.count) files saved"
        case .failed:
            "Failed"
        }
    }
}

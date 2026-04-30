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
        .padding(20)
    }
}
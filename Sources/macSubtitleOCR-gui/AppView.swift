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

// Temporary stubs — will be replaced in later tasks. KEEP all four for now.
struct DropView: View { var body: some View { Text("Drop") } }
struct TracksView: View { var body: some View { Text("Tracks") } }
struct RunView: View { var body: some View { Text("Run") } }
struct DoneView: View { var body: some View { Text("Done") } }

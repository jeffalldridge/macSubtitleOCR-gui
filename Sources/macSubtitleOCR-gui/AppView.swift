import SwiftUI

struct AppView: View {
    @Environment(SubtitleJob.self) private var job

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            appHeader

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .background(.regularMaterial)
    }

    private var appHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("macSubtitleOCR")
                    .font(.title2.weight(.semibold))
                Text("Convert bitmap subtitle tracks to clean SRT files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

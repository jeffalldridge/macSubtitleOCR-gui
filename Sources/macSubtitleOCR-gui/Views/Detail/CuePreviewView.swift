import SwiftUI

/// The selected cue at full size, on a dark card, the way it looks on screen.
struct CuePreviewView: View {
    let track: QueueTrack
    let cueIndex: Int?
    @State private var image: CGImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))

            if let cueIndex, let cue = cueInfo(cueIndex) {
                VStack(spacing: CuePreviewLayout.captionSpacing) {
                    Group {
                        if let image {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("No subtitle image available", systemImage: "photo")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, CuePreviewLayout.imageInset)
                    .padding(.top, 14)

                    HStack(spacing: 10) {
                        Text("Cue \(cueIndex + 1)")
                        Text(cue.timeLabel)
                            .monospacedDigit()
                        if let confidence = cue.confidence {
                            Text("Confidence \(Formatters.percent(Double(confidence)))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.bottom, 8)
                }
            } else {
                Text(track.stream == nil ? "" : "Select a cue to preview it")
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .task(id: "\(track.id)/\(cueIndex ?? -1)") {
            image = nil
            isLoading = false
            guard let cueIndex else { return }
            isLoading = true
            let loaded = await CueImageCache.shared.image(for: track, index: cueIndex)
            guard !Task.isCancelled else { return }
            image = loaded
            isLoading = false
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cueIndex.map { "Preview of cue \($0 + 1)" } ?? "Cue preview")
    }

    private struct Info {
        let timeLabel: String
        let confidence: Float?
    }

    private func cueInfo(_ index: Int) -> Info? {
        if let cue = track.cues.first(where: { $0.index == index }) {
            return Info(timeLabel: Formatters.range(cue.start, cue.end), confidence: cue.confidence)
        }
        guard let stream = track.stream, stream.cues.indices.contains(index) else { return nil }
        let info = stream.cues[index]
        let label = info.end.map { Formatters.range(info.start, $0) } ?? Formatters.clock(info.start)
        return Info(timeLabel: label, confidence: nil)
    }
}

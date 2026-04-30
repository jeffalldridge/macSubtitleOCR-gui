import SwiftUI
import AppKit

struct DoneView: View {
    @Environment(SubtitleJob.self) private var job

    var body: some View {
        VStack(spacing: 18) {
            switch job.phase {
            case .done(let output):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Saved").font(.title2).bold()
                Text(output.lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                    Button("OCR another") { job.reset() }
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let msg):
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Failed").font(.title2).bold()
                Text(msg)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if !job.logLines.isEmpty {
                    DisclosureGroup("Details") {
                        ScrollView {
                            Text(job.logLines.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(minHeight: 120, maxHeight: 200)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                HStack {
                    Button("Try again") { job.reset() }
                        .keyboardShortcut(.defaultAction)
                }
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI
import AppKit

struct DoneView: View {
    @Environment(SubtitleJob.self) private var job

    var body: some View {
        VStack(spacing: 18) {
            switch job.phase {
            case .done(let outputs):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text(outputs.count == 1 ? "Saved" : "Saved \(outputs.count) tracks")
                    .font(.title2).bold()
                if outputs.count == 1, let only = outputs.first {
                    Text(only.lastPathComponent)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([only])
                        }
                        Button("OCR another") { job.reset() }
                            .keyboardShortcut(.defaultAction)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(outputs, id: \.self) { url in
                                HStack {
                                    Text(url.lastPathComponent)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    } label: {
                                        Image(systemName: "magnifyingglass.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Reveal in Finder")
                                }
                                .padding(.vertical, 4).padding(.horizontal, 10)
                            }
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 240)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button("Reveal all in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(outputs)
                        }
                        Button("OCR another") { job.reset() }
                            .keyboardShortcut(.defaultAction)
                    }
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

import SwiftUI
import AppKit

struct DoneView: View {
    @Environment(SubtitleJob.self) private var job

    var body: some View {
        switch job.phase {
        case .done(let outputs):
            successView(outputs: outputs)
        case .failed(let msg):
            failureView(message: msg)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func successView(outputs: [URL]) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(outputs.count == 1 ? "Saved 1 subtitle" : "Saved \(outputs.count) subtitles")
                        .font(.title2.weight(.semibold))
                    Text(savedDirectoryHint(outputs: outputs))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(outputs, id: \.self) { url in
                        SRTPreviewCard(url: url)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                if outputs.count > 1 {
                    Button("Reveal all in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(outputs)
                    }
                } else if let only = outputs.first {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([only])
                    }
                }
                Spacer()
                Button("OCR another") { job.reset() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func failureView(message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Failed").font(.title2).bold()
            Text(message)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func savedDirectoryHint(outputs: [URL]) -> String {
        guard let first = outputs.first else { return "" }
        let dir = first.deletingLastPathComponent().path
        return "Next to your source: \(dir)"
    }
}

private struct SRTPreviewCard: View {
    let url: URL
    @State private var preview: SRTPreview = .empty
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(url.lastPathComponent)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                if loaded && preview.totalCount > 0 {
                    Text("\(preview.totalCount) cues")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }

            if loaded {
                if preview.cues.isEmpty {
                    Text("Empty file — no cues recognized.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(preview.cues, id: \.index) { cue in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(cue.timing)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(minWidth: 90, alignment: .leading)
                                Text(cue.text)
                                    .font(.callout)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                        }
                        if preview.totalCount > preview.cues.count {
                            Text("…and \(preview.totalCount - preview.cues.count) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .task(id: url) {
            preview = (try? SRTPreviewLoader.load(url, maxCues: 3)) ?? .empty
            loaded = true
        }
    }
}

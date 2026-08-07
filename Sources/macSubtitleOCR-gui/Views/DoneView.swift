import AppKit
import SwiftUI

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

    private func successView(outputs: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(outputs.count == 1 ? "Saved 1 subtitle file"
                                            : "Saved \(outputs.count) subtitle files")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let dir = outputs.first?.deletingLastPathComponent() {
                        Text(dir.path(percentEncoded: false))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(dir.path(percentEncoded: false))
                    }
                }
                Spacer()
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(outputs, id: \.self) { url in
                        SRTPreviewCard(url: url)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button(outputs.count > 1 ? "Reveal All in Finder" : "Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                }
                .disabled(outputs.isEmpty)

                Spacer()

                Button("Convert Another File") { job.reset() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Couldn’t finish the conversion")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            if !job.logLines.isEmpty {
                DisclosureGroup("Details") {
                    LogPanel(lines: job.logLines, minHeight: 120)
                        .padding(.top, 4)
                }
                .frame(maxWidth: 520)
            }

            Button("Start Over") { job.reset() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SRTPreviewCard: View {
    let url: URL
    @State private var preview: SRTPreview = .empty
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(url.lastPathComponent)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                if loaded && preview.totalCount > 0 {
                    Text("\(preview.totalCount) cues")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal \(url.lastPathComponent) in Finder")
            }

            if loaded {
                if preview.cues.isEmpty {
                    Text("No cues were recognized in this file.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(preview.cues, id: \.index) { cue in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(cue.timing)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(minWidth: 92, alignment: .leading)
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
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(.separator)
        }
        .task(id: url) {
            preview = (try? SRTPreviewLoader.load(url, maxCues: 3)) ?? .empty
            loaded = true
        }
    }
}

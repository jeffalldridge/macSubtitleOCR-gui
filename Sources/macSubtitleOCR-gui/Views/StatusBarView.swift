import AppKit
import SwiftUI

/// Bottom bar: run progress, the finished summary, and update notices.
struct StatusBarView: View {
    @Environment(ConversionQueue.self) private var queue
    @Environment(AppSettings.self) private var settings
    @Environment(UpdateChecker.self) private var updates

    var body: some View {
        VStack(spacing: 0) {
            if let available = updates.available {
                Divider()
                updateNotice(available)
            }
            switch queue.runState {
            case .running:
                Divider()
                runningBar
            case .finished(let summary):
                Divider()
                finishedBar(summary)
            case .idle:
                EmptyView()
            }
        }
        .background(.bar)
    }

    private var runningBar: some View {
        HStack(spacing: 12) {
            ProgressView(value: queue.overallProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 260)
                .accessibilityLabel("Overall progress")
                .accessibilityValue(Formatters.percent(queue.overallProgress))
            Text(queue.activity)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Formatters.percent(queue.overallProgress))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Cancel") { queue.cancel() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func finishedBar(_ summary: ConversionQueue.RunSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: summary.failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(summary.failed > 0 ? .orange : .green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.headline).font(.headline)
                if let detail = summary.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !summary.outputs.isEmpty {
                Button(summary.outputs.count > 1 ? "Reveal All in Finder" : "Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(summary.outputs)
                }
            }
            Button("Clear Queue") { queue.clear() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .draggable(summary.outputs.first ?? URL(fileURLWithPath: "/"))
    }

    private func updateNotice(_ available: UpdateChecker.Available) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.blue)
            Text("macSubtitleOCR \(available.version) is available.")
            Spacer()
            Link("Download", destination: available.url)
            Button("Skip This Version") { updates.skip(settings: settings) }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .font(.callout)
    }
}

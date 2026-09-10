import AppKit
import SwiftUI

/// The bar along the bottom of the window.
///
/// It is always there, so the window does not resize itself when a run starts
/// and the place to look for "what is happening" never moves. What the queue
/// is doing sits on the left; what the user can do about it sits on the right.
struct QueueStatusBar: View {
    @Environment(ConversionQueue.self) private var queue
    @Environment(AppSettings.self) private var settings
    @Environment(UpdateChecker.self) private var updates

    var body: some View {
        VStack(spacing: 0) {
            if let available = updates.available {
                updateNotice(available)
                Divider()
            }
            HStack(spacing: StatusBarLayout.itemSpacing) {
                summary
                Spacer(minLength: StatusBarLayout.itemSpacing)
                actions
            }
            .padding(.horizontal, StatusBarLayout.horizontalPadding)
            .padding(.vertical, StatusBarLayout.verticalPadding)
            .frame(height: StatusBarLayout.height)
        }
        .controlSize(.small)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Queue status")
    }

    // MARK: - Left

    @ViewBuilder
    private var summary: some View {
        switch queue.runState {
        case .running:
            ProgressView(value: queue.overallProgress)
                .progressViewStyle(.linear)
                .frame(width: StatusBarLayout.progressWidth)
                .accessibilityLabel("Overall progress")
                .accessibilityValue(Formatters.percent(queue.overallProgress))
            Text(Formatters.percent(queue.overallProgress))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(queue.activity)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .help(queue.activity)
        case .finished(let summary):
            Image(systemName: summary.failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(summary.failed > 0 ? .orange : .green)
                .accessibilityHidden(true)
            Text(summary.headline)
            if let detail = summary.detail {
                Text(detail).foregroundStyle(.secondary).lineLimit(1)
            }
        case .idle:
            Text(idleSummary).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// "3 files · 5 of 12 tracks included", which is what the Recognize button
    /// is about to act on.
    private var idleSummary: String {
        guard !queue.isEmpty else { return "No files" }
        let files = queue.files.count
        let tracks = queue.allTracks.count
        let included = queue.includedTracks.count
        var parts = [files == 1 ? "1 file" : "\(files) files"]
        if tracks == 0 {
            parts.append(queue.files.contains(where: { $0.state == .probing })
                         ? "reading tracks…" : "no bitmap subtitle tracks")
        } else if included == tracks {
            parts.append(tracks == 1 ? "1 track included" : "all \(tracks) tracks included")
        } else {
            parts.append("\(included) of \(tracks) tracks included")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Right

    @ViewBuilder
    private var actions: some View {
        switch queue.runState {
        case .running:
            Button("Cancel") { queue.cancel() }
                .keyboardShortcut(.cancelAction)
        case .finished(let summary):
            if !summary.outputs.isEmpty {
                Button(summary.outputs.count > 1 ? "Reveal All in Finder" : "Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(summary.outputs)
                }
            }
            Button("Clear Queue") { queue.clear() }
        case .idle:
            if !queue.isEmpty {
                Button("Clear Queue") { queue.clear() }
            }
        }
    }

    private func updateNotice(_ available: UpdateChecker.Available) -> some View {
        HStack(spacing: StatusBarLayout.itemSpacing) {
            Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
            Text("macSubtitleOCR \(available.version) is available.")
            Spacer()
            Link("Download", destination: available.url)
            Button("Skip This Version") { updates.skip(settings: settings) }
        }
        .padding(.horizontal, StatusBarLayout.horizontalPadding)
        .padding(.vertical, StatusBarLayout.verticalPadding)
    }
}

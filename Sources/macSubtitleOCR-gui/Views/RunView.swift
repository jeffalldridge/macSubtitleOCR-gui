import SwiftUI

struct RunView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ProgressView().controlSize(.small)
                Text(stageLabel).font(.title3)
                Spacer()
            }

            if let url = job.input {
                Text(url.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            ProgressView().progressViewStyle(.linear)

            DisclosureGroup("Log", isExpanded: $showLog) {
                ScrollView {
                    Text(job.logLines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(minHeight: 160, maxHeight: 240)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("Cancel", role: .destructive) { job.reset() }
            }
        }
    }

    private var stageLabel: String {
        if case .running(let stage, let i, let n) = job.phase {
            let stageName: String
            switch stage {
            case .extracting: stageName = "Extracting subtitle track…"
            case .ocr:        stageName = "Running OCR…"
            case .finalizing: stageName = "Saving SRT…"
            }
            if n > 1 { return "Track \(i + 1) of \(n) — \(stageName)" }
            return stageName
        }
        return "Working…"
    }
}

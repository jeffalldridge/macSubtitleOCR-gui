import SwiftUI

struct RunView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(stageLabel)
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text(progressLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let url = job.input {
                        Text(url.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }

                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)

                    Text(stageDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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
            case .extracting: stageName = "Extracting subtitle track..."
            case .ocr:        stageName = "Running OCR..."
            case .finalizing: stageName = "Saving SRT..."
            }
            if n > 1 { return "Track \(i + 1) of \(n) - \(stageName)" }
            return stageName
        }
        return "Working..."
    }

    private var progressValue: Double {
        guard case .running(let stage, let index, let total) = job.phase, total > 0 else {
            return 0
        }
        let stageOffset: Double
        switch stage {
        case .extracting: stageOffset = 0.08
        case .ocr: stageOffset = 0.50
        case .finalizing: stageOffset = 0.94
        }
        return min((Double(index) + stageOffset) / Double(total), 0.98)
    }

    private var progressLabel: String {
        "\(Int((progressValue * 100).rounded()))%"
    }

    private var stageDetail: String {
        guard case .running(let stage, _, _) = job.phase else { return "" }
        switch stage {
        case .extracting:
            return "Pulling only the selected subtitle stream out of the container."
        case .ocr:
            return "Recognizing bitmap captions with Apple's Vision text recognition."
        case .finalizing:
            return "Moving the generated SRT next to the source file with a safe filename."
        }
    }
}

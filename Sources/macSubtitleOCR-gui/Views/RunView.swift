import SwiftUI

struct RunView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(stageLabel)
                            .font(.headline)
                        Spacer()
                        Text(progressLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Conversion progress")
                        .accessibilityValue(progressLabel)

                    Text(stageDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            }

            DisclosureGroup("Log", isExpanded: $showLog) {
                LogPanel(lines: job.logLines)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { job.reset() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var stageLabel: String {
        guard case .running(let stage, let index, let total) = job.phase else {
            return "Working…"
        }
        let stageName = switch stage {
        case .extracting: "Extracting subtitle track…"
        case .ocr: "Running OCR…"
        case .finalizing: "Saving SRT…"
        }
        return total > 1 ? "Track \(index + 1) of \(total) — \(stageName)" : stageName
    }

    private var progressValue: Double {
        guard case .running(let stage, let index, let total) = job.phase, total > 0 else {
            return 0
        }
        let stageOffset = switch stage {
        case Phase.Stage.extracting: 0.08
        case .ocr: 0.50
        case .finalizing: 0.94
        }
        return min((Double(index) + stageOffset) / Double(total), 0.98)
    }

    private var progressLabel: String {
        "\(Int((progressValue * 100).rounded()))%"
    }

    private var stageDetail: String {
        guard case .running(let stage, _, _) = job.phase else { return "" }
        return switch stage {
        case .extracting:
            "Pulling only the selected subtitle stream out of the container."
        case .ocr:
            "Recognizing bitmap captions with Apple’s Vision text recognition."
        case .finalizing:
            "Moving the generated SRT next to the source file with a safe filename."
        }
    }
}

private typealias Phase = SubtitleJob.Phase

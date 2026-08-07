import SwiftUI
import UniformTypeIdentifiers

struct DropView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var isTargeted = false
    @State private var toolchain: ToolchainProbe.MKVToolNix? = ToolchainProbe.mkvtoolnix()

    var body: some View {
        VStack(spacing: 16) {
            if toolchain == nil {
                missingToolchainBanner
            }

            dropTarget
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                    return true
                }
                .opacity(toolchain == nil ? 0.4 : 1)
                .disabled(toolchain == nil || isProbing)
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
        }
    }

    private var dropTarget: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(dropBorderColor)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? AnyShapeStyle(.selection.opacity(0.25))
                                         : AnyShapeStyle(.quinary))
                )

            VStack(spacing: 12) {
                Image(systemName: isProbing ? "waveform" : "arrow.down.doc")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isProbing ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)

                Text(isProbing ? "Reading subtitle tracks…" : "Drop a video or subtitle file")
                    .font(.headline)

                Text(isProbing
                     ? "This usually takes just a moment."
                     : "Supports .mkv, .mks, .sup, .sub, and .idx")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if isProbing {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 4)
                } else {
                    Button("Choose File…") {
                        FileImport.presentOpenPanel(into: job)
                    }
                    .controlSize(.large)
                    .padding(.top, 4)
                }
            }
            .padding(40)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File drop target")
        .accessibilityHint("Drop a video or subtitle file here, or choose one.")
    }

    private var isProbing: Bool {
        if case .probing = job.phase { return true }
        return false
    }

    private var dropBorderColor: Color {
        if isTargeted { return .accentColor }
        if isProbing { return .accentColor.opacity(0.7) }
        return .secondary.opacity(0.6)
    }

    private var missingToolchainBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text("MKVToolNix is required").font(.headline)
                Text("This app uses Homebrew’s mkvtoolnix to read subtitle tracks from MKV files. Install it once, then click “I installed it”.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("brew install mkvtoolnix")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install mkvtoolnix", forType: .string)
                    }
                    .help("Copy the install command to the clipboard")

                    Spacer(minLength: 12)

                    Button("I installed it") {
                        toolchain = ToolchainProbe.mkvtoolnix()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in FileImport.accept(url, into: job) }
        }
    }
}

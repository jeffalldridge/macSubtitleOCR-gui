// Sources/macSubtitleOCR-gui/Views/DropView.swift
import SwiftUI
import UniformTypeIdentifiers

struct DropView: View {
    @Environment(SubtitleJob.self) private var job
    @State private var isTargeted = false
    @State private var toolchain: ToolchainProbe.MKVToolNix? = ToolchainProbe.mkvtoolnix()

    private static let acceptedExtensions: Set<String> = ["mkv", "mks", "sup", "sub", "idx"]

    var body: some View {
        VStack(spacing: 18) {
            if toolchain == nil {
                missingToolchainBanner
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Drop a .mkv, .sup, .sub, or .idx file")
                        .font(.headline)
                    Text("or").foregroundStyle(.secondary)
                    Button("Choose file…") { openFilePicker() }
                        .keyboardShortcut("o")
                }
                .padding(40)
            }
            .frame(minHeight: 240)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
                return true
            }
            .opacity(toolchain == nil ? 0.5 : 1.0)
            .disabled(toolchain == nil)
        }
    }

    private var missingToolchainBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("MKVToolNix is required (dev build only)").font(.headline)
                Text("Install it with Homebrew, then click \u{201C}I installed it\u{201D}. The shipped .app bundles its own copy.")
                    .foregroundStyle(.secondary)
                HStack {
                    Text("brew install mkvtoolnix")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install mkvtoolnix", forType: .string)
                    }
                    Spacer()
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

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.allowedTypes()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { accept(url) }
    }

    private static func allowedTypes() -> [UTType] {
        ["mkv", "mks", "sup", "sub", "idx"].compactMap { UTType(filenameExtension: $0) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { accept(url) }
        }
    }

    private func accept(_ url: URL) {
        guard Self.acceptedExtensions.contains(url.pathExtension.lowercased()) else {
            job.phase = .failed(message: "Unsupported file type: .\(url.pathExtension)")
            return
        }
        Task { await probe(url) }
    }

    private func probe(_ url: URL) async {
        job.input = url
        job.phase = .probing
        guard let mkvtoolnix = toolchain else { return }
        do {
            let prober = TrackProber(mkvmergePath: mkvtoolnix.mkvmerge)
            let tracks = try await prober.probe(url)
            await MainActor.run {
                job.tracks = tracks
                if tracks.isEmpty {
                    job.phase = .failed(message: "No PGS or VobSub tracks found in this file.")
                } else {
                    job.selectedTrack = tracks.first
                    job.advanceToTracks()
                }
            }
        } catch {
            await MainActor.run {
                job.phase = .failed(message: error.localizedDescription)
            }
        }
    }
}

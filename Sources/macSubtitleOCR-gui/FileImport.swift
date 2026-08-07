import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Opening and probing an input file, shared by the drop target and the
/// File ▸ Open… menu command so both routes behave identically.
@MainActor
enum FileImport {
    static let acceptedExtensions: Set<String> = ["mkv", "mks", "sup", "sub", "idx"]

    static var allowedTypes: [UTType] {
        acceptedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    /// True when a new file can be taken on, i.e. we are not mid-probe or mid-run.
    static func canImport(into job: SubtitleJob) -> Bool {
        switch job.phase {
        case .probing, .running: false
        default: true
        }
    }

    static func presentOpenPanel(into job: SubtitleJob) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Open"
        panel.message = "Choose a video or subtitle file to read tracks from."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        accept(url, into: job)
    }

    static func accept(_ url: URL, into job: SubtitleJob) {
        guard acceptedExtensions.contains(url.pathExtension.lowercased()) else {
            job.phase = .failed(message: "Unsupported file type: .\(url.pathExtension)")
            return
        }
        Task { await probe(url, into: job) }
    }

    static func probe(_ url: URL, into job: SubtitleJob) async {
        guard let toolchain = ToolchainProbe.mkvtoolnix() else {
            job.phase = .failed(message: TrackProberError.mkvmergeNotFound.localizedDescription)
            return
        }
        job.input = url
        job.phase = .probing
        do {
            let tracks = try await TrackProber(mkvmergePath: toolchain.mkvmerge).probe(url)
            if tracks.isEmpty {
                job.phase = .failed(message: "No PGS or VobSub subtitle tracks were found in this file.")
            } else {
                job.tracks = tracks
                job.selectDefaultTracks()
                job.advanceToTracks()
            }
        } catch {
            job.phase = .failed(message: error.localizedDescription)
        }
    }
}

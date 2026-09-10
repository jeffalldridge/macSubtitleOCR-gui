import Foundation
import Observation
import SubtitleEngine

/// Where a track is in its journey from container to SRT.
enum TrackStatus: Equatable {
    case idle
    case queued
    case extracting(Double)
    case indexing
    case recognizing(completed: Int, total: Int)
    case saving
    case done
    case failed(String)
    case cancelled

    var isRunning: Bool {
        switch self {
        case .extracting, .indexing, .recognizing, .saving: true
        default: false
        }
    }

    var isFinished: Bool {
        switch self {
        case .done, .failed, .cancelled: true
        default: false
        }
    }

    /// 0…1 within the track's own work.
    var fraction: Double {
        switch self {
        case .idle, .queued: 0
        case .extracting(let p): p * 0.2
        case .indexing: 0.22
        case .recognizing(let done, let total): total > 0 ? 0.25 + 0.72 * Double(done) / Double(total) : 0.25
        case .saving: 0.98
        case .done, .failed, .cancelled: 1
        }
    }

    var label: String {
        switch self {
        case .idle: ""
        case .queued: "Waiting"
        case .extracting: "Reading track…"
        case .indexing: "Indexing cues…"
        case .recognizing(let done, let total):
            "\(done.formatted()) of \(total.formatted())"
        case .saving: "Saving…"
        case .done: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

/// How far the preview stream has loaded (independent of a run).
enum StreamLoadState: Equatable {
    case notLoaded
    case loading(Double)
    case loaded
    case failed(String)
}

/// One bitmap subtitle track inside a queued file.
@Observable
final class QueueTrack: Identifiable {
    let id = UUID()
    let fileID: UUID
    let info: TrackInfo
    var isIncluded: Bool
    var status: TrackStatus = .idle
    var loadState: StreamLoadState = .notLoaded
    var stream: (any SubtitleStream)?
    var cues: [ReviewCue] = []
    var outputURL: URL?
    var issues: [String] = []
    /// Set once the SRT on disk differs from `cues` (debounced writes).
    var hasUnsavedEdits = false

    init(fileID: UUID, info: TrackInfo, isIncluded: Bool) {
        self.fileID = fileID
        self.info = info
        self.isIncluded = isIncluded
    }

    var languageName: String { LanguageCode.displayName(info.preferredLanguageTag) }

    /// "English" or "English — SDH".
    var title: String {
        if let name = info.name, !name.isEmpty { return "\(languageName) — \(name)" }
        return languageName
    }

    /// "PGS · Track 3".
    var subtitle: String {
        "\(info.format.displayName) · Track \(info.id)"
    }

    var cueCount: Int? {
        if !cues.isEmpty { return cues.count }
        return stream?.cues.count
    }

    var reviewCount: Int { cues.filter(\.needsReview).count }
    var editedCount: Int { cues.filter(\.isEdited).count }

    var hasResults: Bool { status == .done && !cues.isEmpty }
}

/// A file the user added.
@Observable
final class QueueFile: Identifiable {
    enum State: Equatable {
        case probing
        case ready(ContainerInfo)
        case failed(String)
    }

    let id = UUID()
    let source: SubtitleSource
    var state: State = .probing
    var tracks: [QueueTrack] = []
    var fileSize: Int64?

    init(source: SubtitleSource) {
        self.source = source
        fileSize = (try? source.primaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    var url: URL { source.primaryURL }
    var displayName: String { source.displayName }

    var info: ContainerInfo? {
        if case .ready(let info) = state { return info }
        return nil
    }

    var includedTracks: [QueueTrack] { tracks.filter(\.isIncluded) }

    /// "2 PGS tracks · 1 text track"
    var summary: String {
        switch state {
        case .probing:
            return "Reading…"
        case .failed(let message):
            return message
        case .ready(let info):
            var parts: [String] = []
            let pgs = tracks.filter { $0.info.format == .pgs }.count
            let vobsub = tracks.filter { $0.info.format == .vobsub }.count
            if pgs > 0 { parts.append("\(pgs) PGS track\(pgs == 1 ? "" : "s")") }
            if vobsub > 0 { parts.append("\(vobsub) VobSub track\(vobsub == 1 ? "" : "s")") }
            let other = info.otherSubtitleCodecs.count
            if other > 0 { parts.append("\(other) text track\(other == 1 ? "" : "s")") }
            if parts.isEmpty { parts.append("No bitmap subtitle tracks") }
            return parts.joined(separator: " · ")
        }
    }
}

/// What is selected in the sidebar.
enum SidebarSelection: Hashable {
    case file(UUID)
    case track(UUID)
}

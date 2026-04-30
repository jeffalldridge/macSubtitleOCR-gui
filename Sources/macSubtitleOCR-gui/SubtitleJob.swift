import Foundation
import Observation

@MainActor
@Observable
public final class SubtitleJob {
    public enum Phase: Equatable {
        case idle
        case probing
        case tracks
        case running(stage: Stage, currentTrackIndex: Int, totalTracks: Int)
        case done(outputs: [URL])
        case failed(message: String)

        public enum Stage: Equatable {
            case extracting
            case ocr
            case finalizing
        }
    }

    public var input: URL?
    public var tracks: [Track] = []
    public var selectedTrackIDs: Set<Track.ID> = []
    public var options: OCRRunner.Options = .init()
    public var phase: Phase = .idle
    public var logLines: [String] = []
    public var error: Error?
    @ObservationIgnored private var activeTask: Task<Void, Never>?

    public init() {}

    public var selectedTracks: [Track] {
        get { tracks.filter { selectedTrackIDs.contains($0.id) } }
        set { selectedTrackIDs = Set(newValue.map(\.id)) }
    }

    public func advanceToTracks() {
        phase = .tracks
    }

    public func selectDefaultTrack() {
        guard let track = Track.bestDefault(from: tracks, preferredLanguages: options.languages) else {
            selectedTrackIDs = []
            return
        }
        selectedTrackIDs = [track.id]
    }

    public func startOCR() {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            await OCRPipeline.run(job: self)
            activeTask = nil
        }
    }

    public func cancelRunningWork() {
        activeTask?.cancel()
        activeTask = nil
    }

    public func reset() {
        cancelRunningWork()
        input = nil
        tracks = []
        selectedTrackIDs = []
        options = .init()
        phase = .idle
        logLines = []
        error = nil
    }

    public func appendLog(_ line: String) {
        logLines.append(line)
    }
}

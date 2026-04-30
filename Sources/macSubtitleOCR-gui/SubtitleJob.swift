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
    public var selectedTracks: Set<Track> = []
    public var options: OCRRunner.Options = .init()
    public var phase: Phase = .idle
    public var logLines: [String] = []
    public var error: Error?

    public init() {}

    public func advanceToTracks() {
        phase = .tracks
    }

    public func reset() {
        input = nil
        tracks = []
        selectedTracks = []
        options = .init()
        phase = .idle
        logLines = []
        error = nil
    }

    public func appendLog(_ line: String) {
        logLines.append(line)
    }
}

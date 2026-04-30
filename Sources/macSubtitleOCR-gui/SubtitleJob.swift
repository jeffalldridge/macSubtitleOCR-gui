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

    public init() {
        self.options = Self.loadPersistedOptions() ?? .init()
    }

    public var selectedTracks: [Track] {
        get { tracks.filter { selectedTrackIDs.contains($0.id) } }
        set { selectedTrackIDs = Set(newValue.map(\.id)) }
    }

    public func advanceToTracks() {
        phase = .tracks
    }

    /// Tick all tracks whose language matches the user's language preference,
    /// ordered (default first, non-forced first, lower id first). Falls back to
    /// `Track.bestDefault` when no track matches the preference.
    public func selectDefaultTracks() {
        let matches = Track.matching(tracks: tracks, preferredLanguages: options.languages)
        if !matches.isEmpty {
            selectedTrackIDs = Set(matches.map(\.id))
            return
        }
        if let fallback = Track.bestDefault(from: tracks, preferredLanguages: options.languages) {
            selectedTrackIDs = [fallback.id]
        } else {
            selectedTrackIDs = []
        }
    }

    public func startOCR() {
        Self.savePersistedOptions(options)
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
        // Preserve the user's persisted preferences across resets so a fresh
        // file inherits the language / invert / custom-words they last chose.
        options = Self.loadPersistedOptions() ?? .init()
        phase = .idle
        logLines = []
        error = nil
    }

    // MARK: - Persistence

    private static let optionsDefaultsKey = "macSubtitleOCRGUI.OCROptions.v1"

    private static func loadPersistedOptions() -> OCRRunner.Options? {
        guard let data = UserDefaults.standard.data(forKey: optionsDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(OCRRunner.Options.self, from: data)
    }

    private static func savePersistedOptions(_ options: OCRRunner.Options) {
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: optionsDefaultsKey)
        }
    }

    public func appendLog(_ line: String) {
        logLines.append(line)
    }
}

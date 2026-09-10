import Foundation
import Observation
import os
import SubtitleEngine

/// Everything on screen: the files, their tracks, the options for this run,
/// and the run itself.
@Observable
final class ConversionQueue {
    struct RunSummary: Equatable {
        var saved: Int
        var failed: Int
        var cancelled: Int
        var reviewCount: Int
        var outputs: [URL]

        var headline: String {
            if saved == 0 && failed == 0 && cancelled > 0 { return "Cancelled" }
            var text = saved == 1 ? "Saved 1 subtitle file" : "Saved \(saved) subtitle files"
            if failed > 0 { text += " · \(failed) failed" }
            if cancelled > 0 { text += " · \(cancelled) cancelled" }
            return text
        }

        var detail: String? {
            guard saved > 0 else { return nil }
            if reviewCount == 0 { return "No cues need review" }
            return reviewCount == 1 ? "1 cue to review" : "\(reviewCount) cues to review"
        }
    }

    enum RunState: Equatable {
        case idle
        case running
        case finished(RunSummary)
    }

    private static let logger = Logger(subsystem: "com.tentstudios.macSubtitleOCR", category: "app.queue")

    var files: [QueueFile] = []
    var selection: SidebarSelection?
    var runOptions: RunOptions
    var runState: RunState = .idle
    /// 0…1 across every included track.
    var overallProgress: Double = 0
    /// "Recognizing English (SDH) · 312 of 1,204 cues"
    var activity: String = ""
    /// Incremented when a run finishes, for haptics and notifications.
    var finishedRunCount = 0

    let settings: AppSettings
    let cache: StreamCache

    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var probeTasks: [UUID: Task<Void, Never>] = [:]

    init(settings: AppSettings, cache: StreamCache = .default) {
        self.settings = settings
        self.cache = cache
        runOptions = RunOptions(settings: settings)
    }

    // MARK: - Lookup

    var isEmpty: Bool { files.isEmpty }
    var isRunning: Bool { runState == .running }

    var allTracks: [QueueTrack] { files.flatMap(\.tracks) }
    var includedTracks: [QueueTrack] { allTracks.filter(\.isIncluded) }
    var completedTracks: [QueueTrack] { allTracks.filter { $0.status == .done } }
    var outputs: [URL] { allTracks.compactMap(\.outputURL) }

    var canRun: Bool { !isRunning && !includedTracks.isEmpty && files.allSatisfy { $0.state != .probing } }

    func file(id: UUID) -> QueueFile? { files.first { $0.id == id } }
    func track(id: UUID) -> QueueTrack? { allTracks.first { $0.id == id } }
    func file(for track: QueueTrack) -> QueueFile? { file(id: track.fileID) }

    var selectedFile: QueueFile? {
        switch selection {
        case .file(let id): file(id: id)
        case .track(let id): track(id: id).flatMap(file(for:))
        case nil: nil
        }
    }

    var selectedTrack: QueueTrack? {
        if case .track(let id) = selection { return track(id: id) }
        return nil
    }

    // MARK: - Adding and removing

    /// Add files. Unsupported and duplicate URLs are ignored; VobSub pairs
    /// are added once.
    func add(urls: [URL]) {
        var seen = Set(files.flatMap { $0.source.urls.map(\.standardizedFileURL) })
        for url in urls {
            let source: SubtitleSource
            do {
                source = try SubtitleSource.open(url)
            } catch {
                Self.logger.info("Ignoring \(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }
            let key = source.primaryURL.standardizedFileURL
            guard !seen.contains(key) else { continue }
            seen.formUnion(source.urls.map(\.standardizedFileURL))

            let file = QueueFile(source: source)
            files.append(file)
            RecentFiles.note(url)
            probe(file)
        }
        if selection == nil, let first = files.first {
            selection = .file(first.id)
        }
        if case .finished = runState, !files.isEmpty { runState = .idle }
    }

    private func probe(_ file: QueueFile) {
        let source = file.source
        probeTasks[file.id] = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ContainerInfo, Error> in
                Result { try source.probe() }
            }.value
            guard !Task.isCancelled, files.contains(where: { $0.id == file.id }) else { return }
            switch result {
            case .success(let info):
                let tracks = info.tracks.map { QueueTrack(fileID: file.id, info: $0, isIncluded: false) }
                file.tracks = tracks
                file.state = .ready(info)
                selectDefaultTracks(in: file)
                if selection == .file(file.id), tracks.count == 1 {
                    selection = .track(tracks[0].id)
                }
            case .failure(let error):
                file.state = .failed(error.localizedDescription)
            }
            probeTasks[file.id] = nil
        }
    }

    func remove(_ file: QueueFile) {
        guard !isRunning else { return }
        probeTasks[file.id]?.cancel()
        probeTasks[file.id] = nil
        files.removeAll { $0.id == file.id }
        if selectedFile?.id == file.id || selectedFile == nil {
            selection = files.first.map { .file($0.id) }
        }
    }

    func clear() {
        guard !isRunning else { return }
        probeTasks.values.forEach { $0.cancel() }
        probeTasks.removeAll()
        files.removeAll()
        selection = nil
        runState = .idle
        overallProgress = 0
        activity = ""
        runOptions = RunOptions(settings: settings)
    }

    // MARK: - Inclusion

    /// Include every track whose language matches the run's languages; if
    /// none match, the container's default track; if none, the first.
    func selectDefaultTracks(in file: QueueFile) {
        let wanted = Set(runOptions.languages.compactMap { LanguageCode.alpha2($0) })
        let matches = file.tracks.filter { track in
            guard let code = LanguageCode.alpha2(track.info.preferredLanguageTag) else { return false }
            return wanted.contains(code)
        }
        let chosen: [QueueTrack]
        if !matches.isEmpty {
            chosen = matches
        } else if let fallback = file.tracks.first(where: { $0.info.isDefault && !$0.info.isForced }) ?? file.tracks.first {
            chosen = [fallback]
        } else {
            chosen = []
        }
        let ids = Set(chosen.map(\.id))
        for track in file.tracks { track.isIncluded = ids.contains(track.id) }
    }

    func includeAll(in file: QueueFile? = nil) {
        for track in (file?.tracks ?? allTracks) { track.isIncluded = true }
    }

    func includeNone(in file: QueueFile? = nil) {
        for track in (file?.tracks ?? allTracks) { track.isIncluded = false }
    }

    // MARK: - Preview streams

    /// Load a track's stream for the detail view without running recognition.
    func loadStreamIfNeeded(for track: QueueTrack) {
        guard track.stream == nil, track.loadState == .notLoaded, let file = file(for: track) else { return }
        Task {
            _ = try? await ConversionRunner.loadStream(for: track, in: file, cache: cache)
        }
    }

    // MARK: - Running

    func run() {
        guard canRun else { return }
        let tracks = includedTracks
        for track in tracks {
            track.status = .queued
            track.cues = []
            track.outputURL = nil
        }
        runState = .running
        overallProgress = 0
        activity = "Starting…"

        let options = runOptions
        runTask = Task { [weak self] in
            guard let self else { return }
            var summary = RunSummary(saved: 0, failed: 0, cancelled: 0, reviewCount: 0, outputs: [])
            let total = Double(tracks.count)

            for (position, track) in tracks.enumerated() {
                guard let file = file(for: track) else { continue }
                if Task.isCancelled {
                    track.status = .cancelled
                    summary.cancelled += 1
                    continue
                }
                let progressTask = Task { [weak self] in
                    // Mirror the track's fraction into the overall progress.
                    while !Task.isCancelled {
                        guard let self else { return }
                        overallProgress = (Double(position) + track.status.fraction) / total
                        activity = Self.activityLabel(for: track)
                        try? await Task.sleep(for: .milliseconds(120))
                    }
                }
                do {
                    let url = try await ConversionRunner.run(track: track, in: file, options: options, cache: cache)
                    summary.saved += 1
                    summary.reviewCount += track.reviewCount
                    summary.outputs.append(url)
                } catch is CancellationError {
                    track.status = .cancelled
                    summary.cancelled += 1
                } catch let error as EngineError where error == .cancelled {
                    track.status = .cancelled
                    summary.cancelled += 1
                } catch {
                    track.status = .failed(error.localizedDescription)
                    track.issues.append(error.localizedDescription)
                    summary.failed += 1
                    Self.logger.error("Track \(track.info.id) failed: \(error.localizedDescription)")
                }
                progressTask.cancel()
            }

            overallProgress = 1
            activity = summary.headline
            runState = .finished(summary)
            finishedRunCount += 1
            runTask = nil
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    static func activityLabel(for track: QueueTrack) -> String {
        switch track.status {
        case .queued: "Waiting for \(track.title)"
        case .extracting: "Reading \(track.title)…"
        case .indexing: "Indexing \(track.title)…"
        case .recognizing(let done, let total):
            "Recognizing \(track.title) · \(done.formatted()) of \(total.formatted()) cues"
        case .saving: "Saving \(track.title)…"
        case .done: "Finished \(track.title)"
        case .failed: "\(track.title) failed"
        case .cancelled: "Cancelled \(track.title)"
        case .idle: ""
        }
    }

    // MARK: - Editing results

    /// Write out any edit that a debounce timer has not yet flushed.
    ///
    /// Called when a track's view goes away and when the app is asked to
    /// quit, so that typing a correction and immediately closing the window
    /// does not throw the correction away.
    func flushPendingEdits() {
        for track in allTracks where track.hasUnsavedEdits {
            saveEdits(for: track)
        }
    }

    var hasUnsavedEdits: Bool {
        allTracks.contains { $0.hasUnsavedEdits }
    }

    /// Persist edits for a track (debounced by the caller).
    func saveEdits(for track: QueueTrack) {
        guard let file = file(for: track), track.outputURL != nil else { return }
        do {
            try ConversionRunner.writeSRT(cues: track.cues, for: track, in: file, options: runOptions)
            track.hasUnsavedEdits = false
        } catch {
            track.issues.append("Could not save edits: \(error.localizedDescription)")
        }
    }
}

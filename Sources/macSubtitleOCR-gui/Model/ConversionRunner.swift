import Foundation
import os
import SubtitleEngine

/// Runs one track from container to SRT, updating the track as it goes.
enum ConversionRunner {
    nonisolated private static let logger = Logger(subsystem: "com.tentstudios.macSubtitleOCR", category: "app.run")

    /// Load (or reuse) the track's stream. Extraction runs off the main actor;
    /// the cache is consulted first.
    static func loadStream(for track: QueueTrack, in file: QueueFile, cache: StreamCache) async throws -> any SubtitleStream {
        if let stream = track.stream { return stream }
        // A preview load may already be running; walking the same MKV twice in
        // parallel doubles the work and makes the percentage jump around.
        if let inFlight = track.loadTask {
            return try await inFlight.value
        }
        track.loadState = .loading(0)

        let source = file.source
        let info = track.info
        let progress: @Sendable (Double) -> Void = { value in
            Task { @MainActor in
                if case .loading = track.loadState { track.loadState = .loading(value) }
                if case .extracting = track.status { track.status = .extracting(value) }
            }
        }

        do {
            // Detached, and it has to stay that way: this type is main-actor
            // isolated, so a plain `Task { }` inherits that isolation and walks
            // a multi-gigabyte container on the main thread, freezing the
            // window until it finishes.
            //
            // A detached task does not inherit cancellation either, so that is
            // wired up by hand below. The engine polls `Task.isCancelled`
            // between clusters, which is what makes Cancel work mid-read.
            let siblings = file.tracks.map(\.info)
            let work = Task.detached(priority: .userInitiated) { () throws -> any SubtitleStream in
                try Task.checkCancellation()
                guard source.isContainer else {
                    return try source.loadStream(for: info, progress: progress)
                }

                let key = StreamCache.key(for: source.primaryURL, track: info)
                if let cached = try? cache.loadStream(key: key, format: info.format) {
                    logger.debug("Stream cache hit for \(source.displayName) track \(info.id)")
                    return cached
                }

                // Reading one track means walking the entire container, so
                // pull every bitmap track it has while we are in there. Eight
                // subtitle tracks used to mean eight full passes; the others
                // are now already cached by the time they are asked for.
                let uncached = siblings.filter { sibling in
                    sibling.id == info.id || cache.cachedURLs(
                        for: StreamCache.key(for: source.primaryURL, track: sibling),
                        format: sibling.format) == nil
                }
                let extracted = try source.extract(tracks: uncached, progress: progress)
                try Task.checkCancellation()

                for (number, track) in extracted {
                    guard let sibling = uncached.first(where: { $0.id == number }) else { continue }
                    try? cache.store(track, key: StreamCache.key(for: source.primaryURL, track: sibling))
                }

                guard let mine = extracted[info.id] else { throw EngineError.trackNotFound(info.id) }
                if let cached = try? cache.loadStream(key: key, format: info.format) { return cached }
                return try SubtitleSource.stream(from: mine)
            }
            track.loadTask = work
            defer { track.loadTask = nil }
            let stream = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            track.stream = stream
            track.loadState = .loaded
            track.issues.append(contentsOf: stream.warnings.filter { !track.issues.contains($0) })
            return stream
        } catch is CancellationError {
            track.loadState = .notLoaded
            throw CancellationError()
        } catch {
            track.loadState = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Convert one track. Returns the written SRT.
    static func run(track: QueueTrack, in file: QueueFile, options: RunOptions, cache: StreamCache,
                    claimedNames: Set<String> = []) async throws -> URL {
        track.status = .extracting(0)
        track.cues = []
        track.outputURL = nil

        let stream = try await loadStream(for: track, in: file, cache: cache)
        try Task.checkCancellation()
        track.status = .indexing

        var recognized: [RecognizedCue] = []
        let events = TrackConverter.run(stream: stream,
                                        options: options.recognition,
                                        trackLanguage: track.info.preferredLanguageTag)
        for try await event in events {
            switch event {
            case .indexed(let count):
                track.status = .recognizing(completed: 0, total: count)
            case .progress(let completed, let total):
                track.status = .recognizing(completed: completed, total: total)
            case .cue:
                break
            case .finished(let cues):
                recognized = cues
            }
        }
        try Task.checkCancellation()

        track.status = .saving
        let ends = SRTTiming.resolveEnds(starts: recognized.map(\.start), ends: recognized.map(\.end))
        let cues = zip(recognized, ends).map { ReviewCue(recognized: $0, end: $1) }
        let url = try writeSRT(cues: cues, for: track, in: file, options: options, claimedNames: claimedNames)

        track.cues = cues
        track.outputURL = url
        track.status = .done
        logger.info("Saved \(cues.count) cues to \(url.lastPathComponent)")
        return url
    }

    /// Write (or rewrite) the SRT for a track.
    @discardableResult
    static func writeSRT(cues: [ReviewCue], for track: QueueTrack, in file: QueueFile, options: RunOptions,
                         claimedNames: Set<String> = []) throws -> URL {
        let url: URL
        if let existing = track.outputURL {
            url = existing
        } else {
            let folder = options.outputFolder ?? file.url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            url = OutputNaming.url(for: track.info,
                                   sourceURL: file.url,
                                   fallbackLanguage: options.fallbackLanguage,
                                   outputFolder: options.outputFolder,
                                   conflictPolicy: options.conflictPolicy,
                                   existing: OutputNaming.existingNames(in: folder),
                                   claimed: claimedNames)
        }
        let text = SRTFile.render(cues.map(\.srtCue))
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

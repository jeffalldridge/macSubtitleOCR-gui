import Foundation
import os

/// Recognizes every cue of a stream, reporting progress as it goes.
///
/// Cues are decoded and recognized a few at a time (bounded by
/// `RecognitionOptions.maxConcurrency`). Events arrive as cues complete, in
/// completion order; `.finished` carries the results in cue order.
/// Cancelling the consuming task cancels recognition.
public enum TrackConverter {
    public enum Event: Sendable {
        case indexed(cueCount: Int)
        case progress(completed: Int, total: Int)
        case cue(RecognizedCue)
        case finished([RecognizedCue])
    }

    private static let logger = Logger(subsystem: "com.tentstudios.macSubtitleOCR", category: "engine.ocr")

    public static func run(stream: any SubtitleStream,
                           options: RecognitionOptions,
                           trackLanguage: String? = nil) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await convert(stream: stream, options: options, trackLanguage: trackLanguage,
                                      continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: EngineError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func convert(stream: any SubtitleStream,
                                options: RecognitionOptions,
                                trackLanguage: String?,
                                continuation: AsyncThrowingStream<Event, Error>.Continuation) async throws {
        let signposter = OSSignposter(logger: logger)
        let interval = signposter.beginInterval("recognize")
        defer { signposter.endInterval("recognize", interval) }

        let cues = stream.cues
        let total = cues.count
        continuation.yield(.indexed(cueCount: total))
        guard total > 0 else {
            continuation.yield(.finished([]))
            return
        }

        let supported = await TextRecognizer.supportedLanguages()
        let languages = TextRecognizer.resolvedLanguages(for: trackLanguage, options: options, supported: supported)
        let recognizer = TextRecognizer(languages: languages,
                                        customWords: options.customWords,
                                        automaticLanguageDetection: options.automaticLanguageDetection)
        let english = languages.contains { $0.languageCode?.identifier == "en" }
            || (languages.isEmpty && options.languages.contains { $0.hasPrefix("en") })
        let correctL = options.correctLowercaseL && english
        let limit = max(1, options.maxConcurrency)

        var results = [RecognizedCue?](repeating: nil, count: total)
        var completed = 0

        try await withThrowingTaskGroup(of: RecognizedCue.self) { group in
            var next = 0
            var active = 0

            func enqueue() {
                let index = next
                let info = cues[index]
                next += 1
                active += 1
                group.addTask {
                    try Task.checkCancellation()
                    return try await recognizeCue(index: index, info: info, stream: stream,
                                                  recognizer: recognizer, invert: options.invert,
                                                  correctL: correctL)
                }
            }

            while next < total, active < limit { enqueue() }
            while let cue = try await group.next() {
                active -= 1
                completed += 1
                results[cue.index] = cue
                continuation.yield(.cue(cue))
                continuation.yield(.progress(completed: completed, total: total))
                try Task.checkCancellation()
                while next < total, active < limit { enqueue() }
            }
        }

        continuation.yield(.finished(results.compactMap { $0 }))
    }

    private static func recognizeCue(index: Int,
                                     info: CueInfo,
                                     stream: any SubtitleStream,
                                     recognizer: TextRecognizer,
                                     invert: Bool,
                                     correctL: Bool) async throws -> RecognizedCue {
        guard let bitmap = try stream.bitmap(at: index),
              let image = bitmap.cgImage(style: .recognition(invert: invert), margin: 12) else {
            return RecognizedCue(index: index, start: info.start, end: info.end, text: "", lines: [], hadBitmap: false)
        }
        try Task.checkCancellation()
        let lines = try await recognizer.recognize(image)
        var text = lines.map(\.text).joined(separator: "\n")
        if correctL { text = TextRecognizer.correctLowercaseL(text) }
        return RecognizedCue(index: index, start: info.start, end: info.end, text: text, lines: lines, hadBitmap: true)
    }
}

import Foundation

public enum MKVToolNixExtractorError: Error, LocalizedError {
    case mkvextractFailed(stderr: String, code: Int32)
    case mkvextractNotFound

    public var errorDescription: String? {
        switch self {
        case .mkvextractFailed(let s, let c): "mkvextract exited with code \(c): \(s)"
        case .mkvextractNotFound: "mkvextract not found. Install MKVToolNix: brew install mkvtoolnix"
        }
    }
}

public struct MKVToolNixExtractor: TrackExtractor {
    public let mkvextractPath: URL

    public init(mkvextractPath: URL) {
        self.mkvextractPath = mkvextractPath
    }

    public func extract(input: URL, track: Track) async throws -> URL {
        let output = Self.makeTempOutputURL(track: track)
        do {
            let result = try await ProcessRunner.run(
                executable: mkvextractPath,
                arguments: Self.arguments(input: input, trackID: track.id, output: output)
            )
            if result.terminationStatus != 0 {
                let errStr = String(data: result.stderr, encoding: .utf8) ?? ""
                throw MKVToolNixExtractorError.mkvextractFailed(stderr: errStr, code: result.terminationStatus)
            }
        } catch {
            if error is MKVToolNixExtractorError { throw error }
            if error is CancellationError { throw error }
            throw MKVToolNixExtractorError.mkvextractNotFound
        }
        return output
    }

    static func arguments(input: URL, trackID: Int, output: URL) -> [String] {
        ["tracks", input.path, "\(trackID):\(output.path)"]
    }

    static func makeTempOutputURL(track: Track) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macSubtitleOCR-gui", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("track-\(track.id).\(track.codec.extractedFileExtension)")
    }
}

private extension Track.Codec {
    var extractedFileExtension: String {
        switch self {
        case .pgs: "sup"
        case .vobsub: "idx"
        }
    }
}

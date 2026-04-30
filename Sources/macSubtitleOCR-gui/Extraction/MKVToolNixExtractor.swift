import Foundation

public enum MKVToolNixExtractorError: Error, LocalizedError {
    case mkvextractFailed(stderr: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .mkvextractFailed(let s, let c): "mkvextract exited with code \(c): \(s)"
        }
    }
}

public struct MKVToolNixExtractor: TrackExtractor {
    public let mkvextractPath: URL

    public init(mkvextractPath: URL) {
        self.mkvextractPath = mkvextractPath
    }

    public func extract(input: URL, trackID: Int) async throws -> URL {
        let output = Self.makeTempOutputURL(trackID: trackID)
        let process = Process()
        process.executableURL = mkvextractPath
        process.arguments = Self.arguments(input: input, trackID: trackID, output: output)
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()  // discard

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errStr = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw MKVToolNixExtractorError.mkvextractFailed(stderr: errStr, code: process.terminationStatus)
        }
        return output
    }

    static func arguments(input: URL, trackID: Int, output: URL) -> [String] {
        ["tracks", input.path, "\(trackID):\(output.path)"]
    }

    static func makeTempOutputURL(trackID: Int) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macSubtitleOCR-gui", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("track-\(trackID).sup")
    }
}

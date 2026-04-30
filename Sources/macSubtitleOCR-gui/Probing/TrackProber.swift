import Foundation

public enum TrackProberError: Error, LocalizedError {
    case mkvmergeNotFound
    case mkvmergeFailed(stderr: String, code: Int32)
    case malformedJSON(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .mkvmergeNotFound:
            "mkvmerge not found. Install MKVToolNix: brew install mkvtoolnix"
        case .mkvmergeFailed(let stderr, let code):
            "mkvmerge exited with code \(code): \(stderr)"
        case .malformedJSON(let err):
            "Could not parse mkvmerge JSON: \(err.localizedDescription)"
        }
    }
}

public struct TrackProber {
    public let mkvmergePath: URL

    public init(mkvmergePath: URL) {
        self.mkvmergePath = mkvmergePath
    }

    /// Probe an input file and return its subtitle tracks (PGS/VobSub only).
    public func probe(_ input: URL) async throws -> [Track] {
        let ext = input.pathExtension.lowercased()
        if ext == "mkv" || ext == "mks" {
            let data = try await runMkvmerge(input)
            return try Self.parseMkvmergeJSON(data)
        }
        return Self.syntheticTracks(for: input)
    }

    /// Build a single synthetic track for non-container inputs (.sup, .sub, .idx).
    public static func syntheticTracks(for url: URL) -> [Track] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "sup":
            return [Track(id: 0, codec: .pgs, language: nil, name: nil)]
        case "sub", "idx":
            return [Track(id: 0, codec: .vobsub, language: nil, name: nil)]
        default:
            return []
        }
    }

    /// Parse `mkvmerge -J` output. Pure function, no I/O. PGS + VobSub only.
    public static func parseMkvmergeJSON(_ data: Data) throws -> [Track] {
        struct Root: Decodable { let tracks: [Entry] }
        struct Entry: Decodable {
            let id: Int
            let type: String
            let codec: String
            let properties: Properties?
        }
        struct Properties: Decodable {
            let language: String?
            let track_name: String?
        }

        do {
            let root = try JSONDecoder().decode(Root.self, from: data)
            return root.tracks.compactMap { entry in
                guard entry.type == "subtitles" else { return nil }
                let codec: Track.Codec
                switch entry.codec.lowercased() {
                case let s where s.contains("pgs"): codec = .pgs
                case let s where s.contains("vobsub") || s.contains("vob sub"): codec = .vobsub
                default: return nil
                }
                let lang = entry.properties?.language.flatMap { $0 == "und" ? nil : $0 }
                return Track(id: entry.id, codec: codec, language: lang, name: entry.properties?.track_name)
            }
        } catch {
            throw TrackProberError.malformedJSON(underlying: error)
        }
    }

    private func runMkvmerge(_ input: URL) async throws -> Data {
        let process = Process()
        process.executableURL = mkvmergePath
        process.arguments = ["-J", input.path]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw TrackProberError.mkvmergeNotFound
        }
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errStr = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TrackProberError.mkvmergeFailed(stderr: errStr, code: process.terminationStatus)
        }
        return outData
    }
}

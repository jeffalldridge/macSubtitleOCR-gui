import Foundation

/// A file the user opened, resolved to what it contains.
public enum SubtitleSource: Sendable, Equatable, Hashable {
    case mkv(URL)
    case pgs(URL)
    case vobsub(sub: URL, idx: URL)

    /// Extensions accepted by `open(_:)`, lowercase.
    public static let supportedExtensions: Set<String> = ["mkv", "mks", "sup", "sub", "idx"]

    /// Resolve a URL. VobSub files are paired with their sibling by name.
    public static func open(_ url: URL) throws -> SubtitleSource {
        switch url.pathExtension.lowercased() {
        case "mkv", "mks":
            return .mkv(url)
        case "sup":
            return .pgs(url)
        case "sub":
            return .vobsub(sub: url, idx: try companion(of: url, extension: "idx"))
        case "idx":
            return .vobsub(sub: try companion(of: url, extension: "sub"), idx: url)
        default:
            throw EngineError.unsupportedFileType(url.pathExtension)
        }
    }

    /// Find `Name.<ext>` next to `url`, matching the extension in any case
    /// and returning the name exactly as it is on disk.
    private static func companion(of url: URL, extension ext: String) throws -> URL {
        let directory = url.deletingLastPathComponent()
        let wanted = (url.deletingPathExtension().lastPathComponent + "." + ext).lowercased()
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        if let match = entries.first(where: { $0.lowercased() == wanted }) {
            return directory.appendingPathComponent(match)
        }
        throw EngineError.missingCompanionFile(expected: url.deletingPathExtension().appendingPathExtension(ext))
    }

    /// The file used for naming outputs and for display.
    public var primaryURL: URL {
        switch self {
        case .mkv(let url), .pgs(let url): url
        case .vobsub(let sub, _): sub
        }
    }

    /// Every file that belongs to this source.
    public var urls: [URL] {
        switch self {
        case .mkv(let url), .pgs(let url): [url]
        case .vobsub(let sub, let idx): [sub, idx]
        }
    }

    public var displayName: String { primaryURL.lastPathComponent }

    public var isContainer: Bool {
        if case .mkv = self { return true }
        return false
    }

    /// The tracks inside. Standalone files report one synthetic track.
    public func probe() throws -> ContainerInfo {
        switch self {
        case .mkv(let url):
            return try MKVReader(url: url).probe()
        case .pgs(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { throw EngineError.fileNotFound(url) }
            return ContainerInfo(tracks: [TrackInfo(id: 1, format: .pgs, isDefault: true)])
        case .vobsub(_, let idx):
            let parsed = try VobSubIDX(url: idx)
            return ContainerInfo(tracks: [TrackInfo(id: 1, format: .vobsub, language: parsed.language, isDefault: true)])
        }
    }

    /// Extract a track from a container. Standalone sources return nil
    /// because their file already is the stream.
    public func extract(track: TrackInfo,
                        progress: (@Sendable (Double) -> Void)? = nil) throws -> ExtractedTrack? {
        guard case .mkv(let url) = self else { return nil }
        return try MKVReader(url: url).extract(trackNumber: track.id, progress: progress)
    }

    /// Open a decodable stream for `track`.
    public func loadStream(for track: TrackInfo,
                           progress: (@Sendable (Double) -> Void)? = nil) throws -> any SubtitleStream {
        switch self {
        case .mkv:
            guard let extracted = try extract(track: track, progress: progress) else {
                throw EngineError.trackNotFound(track.id)
            }
            return try Self.stream(from: extracted)
        case .pgs(let url):
            return try PGSStream(url: url)
        case .vobsub(let sub, let idx):
            return try VobSubStream(subURL: sub, idxURL: idx)
        }
    }

    /// Wrap extracted track data as a stream.
    public static func stream(from extracted: ExtractedTrack) throws -> any SubtitleStream {
        switch extracted {
        case .pgs(let data):
            return try PGSStream(data: data)
        case .vobsub(let sub, let idx):
            return try VobSubStream(sub: sub, idx: idx)
        }
    }
}

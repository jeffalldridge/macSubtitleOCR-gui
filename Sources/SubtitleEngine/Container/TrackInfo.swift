import Foundation

/// The bitmap subtitle formats the engine can decode.
public enum BitmapSubtitleFormat: String, Sendable, Codable, CaseIterable {
    /// Blu-ray Presentation Graphics (`S_HDMV/PGS`, `.sup`).
    case pgs
    /// DVD subpictures (`S_VOBSUB`, `.sub` + `.idx`).
    case vobsub

    public var displayName: String {
        switch self {
        case .pgs: "PGS"
        case .vobsub: "VobSub"
        }
    }

    public var codecID: String {
        switch self {
        case .pgs: MatroskaID.Codec.pgs
        case .vobsub: MatroskaID.Codec.vobsub
        }
    }

    public init?(codecID: String) {
        switch codecID {
        case MatroskaID.Codec.pgs: self = .pgs
        case MatroskaID.Codec.vobsub: self = .vobsub
        default: return nil
        }
    }
}

/// One bitmap subtitle track as described by its container.
public struct TrackInfo: Sendable, Hashable, Identifiable, Codable {
    /// Matroska track number (1-based). Standalone `.sup` / `.sub` files use 1.
    public let id: Int
    public let format: BitmapSubtitleFormat
    public let codecID: String
    /// Language as stored in the container, usually ISO 639-2 (`eng`), or nil.
    public let language: String?
    /// IETF BCP 47 tag when the container carries one (`en-US`).
    public let languageBCP47: String?
    public let name: String?
    public let isDefault: Bool
    public let isForced: Bool
    /// Codec private data (the VobSub `.idx` header lines).
    public let codecPrivate: Data?
    /// How this track's frames are compressed, if at all.
    var compression: ContentCompression = .none

    public init(id: Int,
                format: BitmapSubtitleFormat,
                codecID: String? = nil,
                language: String? = nil,
                languageBCP47: String? = nil,
                name: String? = nil,
                isDefault: Bool = false,
                isForced: Bool = false,
                codecPrivate: Data? = nil,
                compression: ContentCompression = .none) {
        self.id = id
        self.format = format
        self.codecID = codecID ?? format.codecID
        self.language = language
        self.languageBCP47 = languageBCP47
        self.name = name
        self.isDefault = isDefault
        self.isForced = isForced
        self.codecPrivate = codecPrivate
        self.compression = compression
    }

    enum CodingKeys: String, CodingKey {
        case id, format, codecID, language, languageBCP47, name, isDefault, isForced, codecPrivate
    }

    /// The most specific language tag available: BCP 47 first, then ISO 639.
    public var preferredLanguageTag: String? {
        if let languageBCP47, !languageBCP47.isEmpty, languageBCP47 != "und" { return languageBCP47 }
        if let language, !language.isEmpty, language != "und" { return language }
        return nil
    }
}

/// What a container holds.
public struct ContainerInfo: Sendable, Equatable {
    public let tracks: [TrackInfo]
    /// Codec IDs of subtitle tracks the engine does not decode (text formats
    /// such as `S_TEXT/UTF8`, or DVB). Reported so the UI can explain them.
    public let otherSubtitleCodecs: [String]
    public let duration: TimeInterval?
    public let title: String?
    /// Nanoseconds per timestamp unit (Matroska default 1 000 000).
    public let timestampScale: UInt64

    public init(tracks: [TrackInfo],
                otherSubtitleCodecs: [String] = [],
                duration: TimeInterval? = nil,
                title: String? = nil,
                timestampScale: UInt64 = 1_000_000) {
        self.tracks = tracks
        self.otherSubtitleCodecs = otherSubtitleCodecs
        self.duration = duration
        self.title = title
        self.timestampScale = timestampScale
    }
}

import Foundation

public struct Track: Identifiable, Hashable, Sendable {
    public enum Codec: String, Sendable {
        case pgs       // S_HDMV/PGS
        case vobsub    // S_VOBSUB

        public var displayName: String {
            switch self {
            case .pgs: "PGS"
            case .vobsub: "VobSub"
            }
        }
    }

    public let id: Int            // mkvmerge track number (or 0 for synthetic)
    public let codec: Codec
    public let language: String?  // ISO 639-2 (e.g. "eng"), as returned by mkvmerge
    public let name: String?

    public init(id: Int, codec: Codec, language: String?, name: String?) {
        self.id = id
        self.codec = codec
        self.language = language
        self.name = name
    }
}

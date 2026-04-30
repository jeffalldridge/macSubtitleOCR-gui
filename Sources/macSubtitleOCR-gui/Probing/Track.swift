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
    public let isDefault: Bool
    public let isForced: Bool

    public init(id: Int,
                codec: Codec,
                language: String?,
                name: String?,
                isDefault: Bool = false,
                isForced: Bool = false) {
        self.id = id
        self.codec = codec
        self.language = language
        self.name = name
        self.isDefault = isDefault
        self.isForced = isForced
    }

    public var displayTitle: String {
        let languageName = language.map(Self.displayName(forLanguageCode:)) ?? "Unknown language"
        return "Track \(id) - \(languageName)"
    }

    public var displaySubtitle: String {
        var parts = [codec.displayName]
        if let name, !name.isEmpty {
            parts.append(name)
        }
        return parts.joined(separator: " - ")
    }

    public var languageBadge: String? {
        language?.uppercased()
    }

    public static func bestDefault(from tracks: [Track], preferredLanguages: String = "en") -> Track? {
        guard tracks.count > 1 else { return tracks.first }

        let candidates = matching(tracks: tracks, preferredLanguages: preferredLanguages, fallback: tracks)
        return candidates.first
    }

    /// Every track whose language is in `preferredLanguages`, sorted by
    /// (default first, non-forced first, lower id first). Empty when no language
    /// preference is set or none match — callers can fall back as they see fit.
    public static func matching(tracks: [Track], preferredLanguages: String) -> [Track] {
        matching(tracks: tracks, preferredLanguages: preferredLanguages, fallback: [])
    }

    private static func matching(tracks: [Track],
                                 preferredLanguages: String,
                                 fallback: [Track]) -> [Track] {
        let preferred = Set(preferredLanguages
            .split(separator: ",")
            .map { normalizeLanguageCode(String($0)) }
            .filter { !$0.isEmpty })

        let matches = preferred.isEmpty ? [] : tracks.filter { track in
            guard let language = track.language else { return false }
            return preferred.contains(Self.normalizeLanguageCode(language))
        }
        let candidates = matches.isEmpty ? fallback : matches

        return candidates.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault && !rhs.isDefault }
            if lhs.isForced != rhs.isForced { return !lhs.isForced && rhs.isForced }
            return lhs.id < rhs.id
        }
    }

    private static func normalizeLanguageCode(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "en", "eng": "eng"
        case "es", "spa", "esl": "spa"
        case "fr", "fre", "fra": "fra"
        case "de", "ger", "deu": "deu"
        case "it", "ita": "ita"
        case "ja", "jpn": "jpn"
        case "ko", "kor": "kor"
        case "pt", "por": "por"
        case "zh", "chi", "zho": "zho"
        default: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func displayName(forLanguageCode code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ??
            Locale.current.localizedString(forIdentifier: code) ??
            code.uppercased()
    }
}

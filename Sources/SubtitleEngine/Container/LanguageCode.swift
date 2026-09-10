import Foundation

/// Language tag helpers.
///
/// Containers store ISO 639-2 codes (`eng`), sometimes the legacy
/// bibliographic variants (`ger`, `fre`), and occasionally BCP 47 tags
/// (`en-US`). Vision wants BCP 47; filenames want three-letter codes; people
/// want names.
public enum LanguageCode {
    /// ISO 639-2/B codes that `Locale` does not understand, mapped to 639-1.
    static let bibliographic: [String: String] = [
        "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "chi": "zh", "cze": "cs",
        "dut": "nl", "fre": "fr", "geo": "ka", "ger": "de", "gre": "el", "ice": "is",
        "mac": "mk", "may": "ms", "mao": "mi", "per": "fa", "rum": "ro", "slo": "sk",
        "tib": "bo", "wel": "cy",
    ]

    /// Codes that mean "unknown" rather than a language.
    static let undetermined: Set<String> = ["und", "mis", "mul", "zxx"]

    /// The ISO 639-1 two-letter code, or nil for unknown / undetermined.
    public static func alpha2(_ raw: String?) -> String? {
        guard let language = language(raw) else { return nil }
        return language.languageCode?.identifier(.alpha2)
    }

    /// The ISO 639-2/T three-letter code (`eng`, `deu`), or nil.
    public static func alpha3(_ raw: String?) -> String? {
        guard let language = language(raw) else { return nil }
        return language.languageCode?.identifier(.alpha3)
    }

    /// A localized name (`English`), `Unknown language`, or the raw code
    /// when it is not a real language code.
    public static func displayName(_ raw: String?) -> String {
        guard let trimmed = trimmed(raw) else { return "Unknown language" }
        if undetermined.contains(trimmed) { return "Unknown language" }
        guard let language = language(trimmed),
              let code = language.languageCode?.identifier,
              let name = Locale.current.localizedString(forLanguageCode: code) else {
            return trimmed
        }
        return name
    }

    /// The best match for `raw` among Vision's supported languages, or nil.
    public static func recognitionLanguage(_ raw: String?, supported: [Locale.Language]) -> Locale.Language? {
        guard let language = language(raw), let code = language.languageCode else { return nil }
        let candidates = supported.filter { $0.languageCode == code }
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }

        // Prefer a script match (zh-Hant → zh-TW), then a region match, then the first.
        let wantedScript = language.script ?? Locale.Language(identifier: language.maximalIdentifier).script
        if let wantedScript,
           let match = candidates.first(where: { Locale.Language(identifier: $0.maximalIdentifier).script == wantedScript }) {
            return match
        }
        if let region = language.region, let match = candidates.first(where: { $0.region == region }) {
            return match
        }
        return candidates[0]
    }

    /// A `Locale.Language` for a container code or BCP 47 tag, or nil when
    /// the value is empty, undetermined, or not a known language.
    public static func language(_ raw: String?) -> Locale.Language? {
        guard let trimmed = trimmed(raw), !undetermined.contains(trimmed) else { return nil }
        let identifier: String
        if let mapped = bibliographic[trimmed] {
            identifier = mapped
        } else {
            identifier = trimmed
        }
        let language = Locale.Language(identifier: identifier)
        guard let code = language.languageCode, code.isISOLanguage else { return nil }
        return language
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

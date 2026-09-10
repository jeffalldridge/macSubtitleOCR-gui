import Foundation
import SubtitleEngine

/// Where an SRT goes and what it is called.
///
/// `<base>.<lang>[.<sanitized-track-name>].srt`, e.g. `Film.eng.srt` or
/// `Film.eng.english-sdh.srt`, so SDH and commentary tracks never collide.
enum OutputNaming {
    /// The language code used in filenames: the track's, else the fallback,
    /// as an ISO 639-2 three-letter code.
    static func languageCode(for track: TrackInfo, fallback: String?) -> String? {
        LanguageCode.alpha3(track.preferredLanguageTag) ?? LanguageCode.alpha3(fallback)
    }

    static func filename(base: String, languageCode: String?, trackName: String?, suffix: Int? = nil) -> String {
        var name = base
        if let languageCode, !languageCode.isEmpty { name += ".\(languageCode)" }
        if let trackName, case let cleaned = sanitize(trackName), !cleaned.isEmpty { name += ".\(cleaned)" }
        if let suffix { name += "-\(suffix)" }
        return name + ".srt"
    }

    /// The destination for a track's SRT.
    ///
    /// - Parameters:
    ///   - existing: names already in the folder (any case), used to avoid
    ///     collisions when the policy is `.addSuffix`.
    static func url(for track: TrackInfo,
                    sourceURL: URL,
                    fallbackLanguage: String?,
                    outputFolder: URL?,
                    conflictPolicy: AppSettings.ConflictPolicy,
                    existing: Set<String>) -> URL {
        let folder = outputFolder ?? sourceURL.deletingLastPathComponent()
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let code = languageCode(for: track, fallback: fallbackLanguage)
        let taken = Set(existing.map { $0.lowercased() })

        let primary = filename(base: base, languageCode: code, trackName: track.name)
        if conflictPolicy == .replace || !taken.contains(primary.lowercased()) {
            return folder.appendingPathComponent(primary)
        }
        var suffix = 1
        while true {
            let candidate = filename(base: base, languageCode: code, trackName: track.name, suffix: suffix)
            if !taken.contains(candidate.lowercased()) {
                return folder.appendingPathComponent(candidate)
            }
            suffix += 1
        }
    }

    /// Read the folder so `url(for:…)` can avoid collisions.
    static func existingNames(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    /// Lowercase; runs of anything that is not a letter or digit become one
    /// dash; leading and trailing dashes are dropped.
    static func sanitize(_ raw: String) -> String {
        var out = ""
        var pendingDash = false
        for scalar in raw.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingDash, !out.isEmpty { out.append("-") }
                pendingDash = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        return out.lowercased()
    }
}

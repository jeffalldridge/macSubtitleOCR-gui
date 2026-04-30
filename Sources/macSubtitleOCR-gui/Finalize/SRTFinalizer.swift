import Foundation

public enum SRTFinalizerError: Error, LocalizedError {
    case noSRTProduced(searched: URL)
    case multipleSRTs(producedDir: URL, count: Int)

    public var errorDescription: String? {
        switch self {
        case .noSRTProduced(let dir):
            "macSubtitleOCR did not produce a .srt file in \(dir.path). The track may be empty or unsupported."
        case .multipleSRTs(let dir, let n):
            "macSubtitleOCR produced \(n) .srt files in \(dir.path) — expected exactly one."
        }
    }
}

public enum SRTFinalizer {
    /// Compute the destination URL for the SRT, avoiding collisions.
    /// Filename shape: `<base>[.<lang>][.<sanitizedTrackName>].srt`
    public static func targetURL(forInput input: URL,
                                 language: String?,
                                 trackName: String? = nil,
                                 existingFiles: Set<URL>) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let langSuffix = language.flatMap { $0.isEmpty ? nil : ".\($0)" } ?? ""
        let nameSuffix: String
        if let s = trackName.flatMap(sanitizeForFilename), !s.isEmpty {
            nameSuffix = ".\(s)"
        } else {
            nameSuffix = ""
        }

        let primary = dir.appendingPathComponent("\(base)\(langSuffix)\(nameSuffix).srt")
        if !existingFiles.contains(primary) { return primary }

        for n in 1... {
            let candidate = dir.appendingPathComponent("\(base)\(langSuffix)\(nameSuffix)-\(n).srt")
            if !existingFiles.contains(candidate) { return candidate }
        }
        return primary  // unreachable
    }

    /// Move the produced SRT next to `inputURL`. Returns the final URL.
    public static func finalize(producedSRTDir: URL,
                                inputURL: URL,
                                language: String?,
                                trackName: String? = nil) throws -> URL {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: producedSRTDir,
                                                  includingPropertiesForKeys: nil)
        let srts = contents.filter { $0.pathExtension.lowercased() == "srt" }

        guard let produced = srts.first else {
            throw SRTFinalizerError.noSRTProduced(searched: producedSRTDir)
        }
        if srts.count > 1 {
            throw SRTFinalizerError.multipleSRTs(producedDir: producedSRTDir, count: srts.count)
        }

        let dir = inputURL.deletingLastPathComponent()
        let existing = Set(((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []))
        let target = targetURL(forInput: inputURL,
                               language: language,
                               trackName: trackName,
                               existingFiles: existing)

        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        try fm.moveItem(at: produced, to: target)
        return target
    }

    /// Lowercases, replaces non-alphanumeric runs with single dash, trims dashes.
    /// "English SDH" -> "english-sdh"; "Director's Commentary" -> "director-s-commentary"
    public static func sanitizeForFilename(_ raw: String) -> String {
        var out = ""
        var lastWasDash = true  // suppresses leading dashes
        for scalar in raw.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.append(Character(scalar))
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        if out.hasSuffix("-") { out.removeLast() }
        return out.lowercased()
    }
}

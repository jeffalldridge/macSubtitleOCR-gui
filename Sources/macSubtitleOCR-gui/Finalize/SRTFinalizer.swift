import Foundation

public enum SRTFinalizerError: Error, LocalizedError {
    case noSRTProduced(searched: URL)
    case multipleSRTs(producedDir: URL, count: Int)

    public var errorDescription: String? {
        switch self {
        case .noSRTProduced(let dir):
            "macSubtitleOCR did not produce a .srt file in \(dir.path). The track may be empty or unsupported."
        case .multipleSRTs(let dir, let n):
            "macSubtitleOCR produced \(n) .srt files in \(dir.path) — expected exactly one. " +
                "(This usually means a single-track extraction wasn't really single-track.)"
        }
    }
}

public enum SRTFinalizer {
    /// Compute the destination URL for the SRT, avoiding collisions.
    public static func targetURL(forInput input: URL, language: String?, existingFiles: Set<URL>) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let suffix = language.flatMap { $0.isEmpty ? nil : ".\($0)" } ?? ""

        let primary = dir.appendingPathComponent("\(base)\(suffix).srt")
        if !existingFiles.contains(primary) { return primary }

        for n in 1... {
            let candidate = dir.appendingPathComponent("\(base)\(suffix)-\(n).srt")
            if !existingFiles.contains(candidate) { return candidate }
        }
        return primary  // unreachable
    }

    /// Move the produced SRT next to `inputURL`. Returns the final URL.
    public static func finalize(producedSRTDir: URL, inputURL: URL, language: String?) throws -> URL {
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
        let target = targetURL(forInput: inputURL, language: language, existingFiles: existing)

        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        try fm.moveItem(at: produced, to: target)
        return target
    }
}

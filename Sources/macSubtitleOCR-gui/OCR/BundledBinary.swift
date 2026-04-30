import Foundation

public enum BundledBinaryError: Error, LocalizedError {
    case notFound(searched: [URL])

    public var errorDescription: String? {
        switch self {
        case .notFound(let searched):
            "Could not find the macSubtitleOCR binary. Searched:\n" +
                searched.map { "  - \($0.path)" }.joined(separator: "\n") +
                "\n\nRun `make build` to compile and embed it."
        }
    }
}

public enum BundledBinary {
    /// Resolve the path to the embedded macSubtitleOCR binary, trying:
    ///   1. Bundle.main resources (assembled .app)
    ///   2. Bundle.module resources (swift run / swift test in this package)
    ///   3. Adjacent to the executable (post-build copy beside `swift run` output)
    ///   4. Vendored submodule build artifact (developer fallback)
    public static func resolve() throws -> URL {
        let candidates = bundledPaths() + devFallbackPaths()
        if let url = firstExisting(in: candidates) { return url }
        throw BundledBinaryError.notFound(searched: candidates)
    }

    static func bundledPaths() -> [URL] {
        var paths: [URL] = []
        if let main = Bundle.main.url(forResource: "macSubtitleOCR", withExtension: nil) {
            paths.append(main)
        }
        if let module = Bundle.module.url(forResource: "macSubtitleOCR", withExtension: nil) {
            paths.append(module)
        }
        // Adjacent to the running executable (Contents/MacOS/...)
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            paths.append(exe.appendingPathComponent("macSubtitleOCR"))
        }
        return paths
    }

    static func devFallbackPaths() -> [URL] {
        // Walk up from this source file to find Vendor/macSubtitleOCR/.build/release/macSubtitleOCR
        let here = URL(fileURLWithPath: #filePath)
        var dir = here
        for _ in 0..<8 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir
                .appendingPathComponent("Vendor/macSubtitleOCR/.build/release/macSubtitleOCR")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return [candidate]
            }
        }
        // Even if not present, return the path so error messages show what we tried
        let projectRoot = here
            .deletingLastPathComponent()  // OCR
            .deletingLastPathComponent()  // macSubtitleOCR-gui
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // repo root
        return [projectRoot.appendingPathComponent("Vendor/macSubtitleOCR/.build/release/macSubtitleOCR")]
    }

    static func firstExisting(in candidates: [URL]) -> URL? {
        let fm = FileManager.default
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }
}

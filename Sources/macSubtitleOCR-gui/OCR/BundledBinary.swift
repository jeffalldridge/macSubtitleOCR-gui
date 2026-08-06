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
    static let binaryName = "macSubtitleOCR"

    /// Name of the resource bundle SwiftPM generates for this target.
    static let resourceBundleName = "macSubtitleOCR-gui_macSubtitleOCR-gui"

    /// Resolve the path to the embedded macSubtitleOCR binary, trying:
    ///   1. Bundle.main resources (assembled .app)
    ///   2. SwiftPM resource bundle (swift run / swift test in this package)
    ///   3. Adjacent to the executable (post-build copy beside `swift run` output)
    ///   4. Vendored submodule build artifact (developer fallback)
    public static func resolve() throws -> URL {
        let candidates = bundledPaths() + devFallbackPaths()
        if let url = firstExisting(in: candidates) { return url }
        throw BundledBinaryError.notFound(searched: candidates)
    }

    /// Locate SwiftPM's generated resource bundle *without* trapping.
    ///
    /// Deliberately does not use `Bundle.module`: SwiftPM's generated accessor
    /// looks only in `Bundle.main.bundleURL` and a path hardcoded to the build
    /// machine's `.build` directory, then calls `Swift.fatalError()`. Inside our
    /// hand-assembled `.app` neither exists on an end user's machine, so merely
    /// reading it killed the app with SIGTRAP (issue #3). The bundle is optional
    /// here — it is a development convenience, not a shipping requirement.
    static func moduleResourceBundle() -> Bundle? {
        let searchDirs = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }

        for dir in searchDirs {
            let url = dir.appendingPathComponent(resourceBundleName + ".bundle")
            if let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }

    static func bundledPaths(mainBundle: Bundle = .main,
                             moduleBundle: Bundle? = BundledBinary.moduleResourceBundle()) -> [URL] {
        var paths: [URL] = []
        if let main = mainBundle.url(forResource: binaryName, withExtension: nil) {
            paths.append(main)
        }
        if let module = moduleBundle?.url(forResource: binaryName, withExtension: nil) {
            paths.append(module)
        }
        // Adjacent to the running executable (Contents/MacOS/...)
        if let exe = mainBundle.executableURL?.deletingLastPathComponent() {
            paths.append(exe.appendingPathComponent(binaryName))
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

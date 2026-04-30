import Foundation

public enum ToolchainProbe {
    /// Default fallback paths for tools installed via Homebrew on Apple Silicon and Intel.
    public static let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Look up an executable by name in the given paths.
    public static func locate(_ name: String, searchPaths: [String]) -> URL? {
        let fm = FileManager.default
        for dir in searchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Locate a tool, checking $PATH and the Homebrew defaults.
    public static func locate(_ name: String) -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathDirs = path.split(separator: ":").map(String.init)
        return locate(name, searchPaths: pathDirs + homebrewPaths)
    }

    /// Look for an executable inside the running app's bundled Resources.
    /// Returns nil when running outside an .app bundle (e.g. `swift run` / tests).
    public static func locateInBundle(_ name: String) -> URL? {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { return nil }
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    public struct MKVToolNix {
        public let mkvmerge: URL
        public let mkvextract: URL
    }

    /// Resolve mkvtoolnix binaries. Bundled (.app Resources) win over system installs.
    /// Returns nil only when neither bundled nor system binaries are present.
    public static func mkvtoolnix() -> MKVToolNix? {
        if let merge = locateInBundle("mkvmerge"),
           let extract = locateInBundle("mkvextract") {
            return MKVToolNix(mkvmerge: merge, mkvextract: extract)
        }
        guard let merge = locate("mkvmerge"), let extract = locate("mkvextract") else { return nil }
        return MKVToolNix(mkvmerge: merge, mkvextract: extract)
    }
}

import Foundation

/// Where a run writes its subtitle files.
///
/// The default puts each `.srt` beside the film it came from, which is where
/// every video player looks for it without being told. The alternatives are
/// for people who keep subtitles somewhere else, and for people who want to
/// decide each time.
enum OutputDestination: Equatable {
    /// Beside the source file.
    case nextToSource
    /// A folder chosen once and remembered.
    case folder(URL)
    /// Ask when the run starts.
    case askEachTime

    /// What the toolbar shows.
    var menuTitle: String {
        switch self {
        case .nextToSource: "Next to the film"
        case .folder(let url): url.lastPathComponent
        case .askEachTime: "Ask each time"
        }
    }

    /// The full description, for a tooltip.
    var detail: String {
        switch self {
        case .nextToSource:
            "Each subtitle file is written beside the file it came from, where players look for it."
        case .folder(let url):
            "Subtitle files are written to \(url.path(percentEncoded: false))."
        case .askEachTime:
            "You choose a folder each time you make subtitles."
        }
    }

    /// The folder a run should write to, or nil for "beside the source".
    ///
    /// `askEachTime` has no answer of its own; the run asks first and passes
    /// what it was given.
    var resolvedFolder: URL? {
        if case .folder(let url) = self { return url }
        return nil
    }

    var asksBeforeRunning: Bool { self == .askEachTime }
}

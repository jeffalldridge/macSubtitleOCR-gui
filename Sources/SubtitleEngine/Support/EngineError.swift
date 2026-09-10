import Foundation

/// Errors surfaced by the engine. Messages are written for the UI.
public enum EngineError: Error, LocalizedError, Equatable, Sendable {
    case fileNotFound(URL)
    case notMatroska(URL)
    case noTracksElement
    case trackNotFound(Int)
    case unsupportedFileType(String)
    case missingCompanionFile(expected: URL)
    case invalidData(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            "The file “\(url.lastPathComponent)” could not be found."
        case .notMatroska(let url):
            "“\(url.lastPathComponent)” is not a Matroska (MKV) file."
        case .noTracksElement:
            "The file has no track list. It may be truncated or damaged."
        case .trackNotFound(let number):
            "Track \(number) was not found in the file."
        case .unsupportedFileType(let ext):
            "Files of type “.\(ext)” are not supported. Choose an MKV, MKS, SUP, SUB, or IDX file."
        case .missingCompanionFile(let expected):
            "VobSub subtitles come as a pair. “\(expected.lastPathComponent)” was not found next to the file you chose."
        case .invalidData(let detail):
            "The subtitle data could not be read: \(detail)"
        case .cancelled:
            "The operation was cancelled."
        }
    }
}

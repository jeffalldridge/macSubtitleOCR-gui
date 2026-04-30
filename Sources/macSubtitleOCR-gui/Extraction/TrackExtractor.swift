import Foundation

public protocol TrackExtractor: Sendable {
    /// Extract a single track from the given container into a standalone file.
    /// Returns the URL of the extracted file (caller is responsible for cleanup).
    func extract(input: URL, trackID: Int) async throws -> URL
}

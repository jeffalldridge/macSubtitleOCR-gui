import Foundation

/// Fixture files are located relative to this source file, never through
/// `Bundle.module`: the app's packaging history makes that accessor a
/// liability, and a plain path works identically under `swift test` and Xcode.
enum Fixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static let sintelMKS = url("sintel.mks")
    static let sintelSUP = url("sintel.sup")
    static let sintelSUB = url("sintel.sub")
    static let sintelIDX = url("sintel.idx")
    static let sintelSRT = url("sintel.srt")
}

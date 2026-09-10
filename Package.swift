// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "macSubtitleOCR-gui",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SubtitleEngine", targets: ["SubtitleEngine"]),
        .executable(name: "macSubtitleOCR-gui", targets: ["macSubtitleOCR-gui"]),
    ],
    targets: [
        // Pure Swift, no UI: Matroska reading, PGS/VobSub decoding, Vision
        // recognition, SRT writing. Nonisolated so it can run anywhere.
        .target(
            name: "SubtitleEngine",
            path: "Sources/SubtitleEngine",
            exclude: ["UPSTREAM.md"]
        ),
        // The SwiftUI app. UI code defaults to the main actor.
        .executableTarget(
            name: "macSubtitleOCR-gui",
            dependencies: ["SubtitleEngine"],
            path: "Sources/macSubtitleOCR-gui",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "SubtitleEngineTests",
            dependencies: ["SubtitleEngine"],
            path: "Tests/SubtitleEngineTests",
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "macSubtitleOCR-guiTests",
            dependencies: ["macSubtitleOCR-gui"],
            path: "Tests/macSubtitleOCR-guiTests",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macSubtitleOCR-gui",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "macSubtitleOCR-gui", targets: ["macSubtitleOCR-gui"]),
    ],
    targets: [
        .executableTarget(
            name: "macSubtitleOCR-gui",
            path: "Sources/macSubtitleOCR-gui",
            exclude: ["Resources/README.md"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "macSubtitleOCR-guiTests",
            dependencies: ["macSubtitleOCR-gui"],
            path: "Tests/macSubtitleOCR-guiTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)

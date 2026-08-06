import SwiftUI

/// Real entry point, so `--self-check` can run headlessly and exit before any
/// SwiftUI/AppKit setup (no window, no Dock icon). See `SelfCheck`.
@main
enum EntryPoint {
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            exit(SelfCheck.run())
        }
        macSubtitleOCRGUIApp.main()
    }
}

struct macSubtitleOCRGUIApp: App {
    @State private var job = SubtitleJob()

    var body: some Scene {
        WindowGroup("macSubtitleOCR") {
            AppView()
                .environment(job)
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 680, height: 520)
    }
}

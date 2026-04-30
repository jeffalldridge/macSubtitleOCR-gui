import SwiftUI

@main
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

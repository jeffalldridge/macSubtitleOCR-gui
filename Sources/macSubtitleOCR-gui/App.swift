import SwiftUI

@main
struct macSubtitleOCRGUIApp: App {
    @State private var job = SubtitleJob()

    var body: some Scene {
        WindowGroup("macSubtitleOCR") {
            AppView()
                .environment(job)
                .frame(minWidth: 560, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}

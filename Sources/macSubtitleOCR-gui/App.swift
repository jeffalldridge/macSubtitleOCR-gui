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
        WindowGroup {
            AppView()
                .environment(job)
        }
        // contentMinSize lets the user resize freely above a sensible floor;
        // contentSize would pin the window to its content and fight resizing.
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 580)
        .commands {
            // A single-window utility has no concept of "New".
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    FileImport.presentOpenPanel(into: job)
                }
                .keyboardShortcut("o")
                .disabled(!FileImport.canImport(into: job))

                Button("Close File") {
                    job.reset()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(job.input == nil)
            }
            CommandGroup(replacing: .help) {
                Link("macSubtitleOCR-gui Help",
                     destination: URL(string: "https://jeffalldridge.github.io/macSubtitleOCR-gui/")!)
                Link("Report an Issue…",
                     destination: URL(string: "https://github.com/jeffalldridge/macSubtitleOCR-gui/issues/new/choose")!)
            }
        }
    }
}

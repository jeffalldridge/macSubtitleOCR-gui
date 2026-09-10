import AppKit
import SwiftUI

struct AppCommands: Commands {
    let queue: ConversionQueue
    let ui: AppUIState
    let settings: AppSettings
    let updates: UpdateChecker

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About macSubtitleOCR") { AboutPanel.show() }
            Button("Check for Updates…") {
                Task { await updates.check(settings: settings, userInitiated: true) }
            }
            .disabled(updates.isChecking)
        }

        CommandGroup(replacing: .newItem) {
            Button("Open…") { FileImport.presentOpenPanel(into: queue) }
                .keyboardShortcut("o")
                .disabled(queue.isRunning)

            Menu("Open Recent") {
                let recent = RecentFiles.urls
                if recent.isEmpty {
                    Text("No Recent Files")
                } else {
                    ForEach(recent, id: \.self) { url in
                        Button(url.lastPathComponent) { queue.add(urls: [url]) }
                    }
                    Divider()
                    Button("Clear Menu") { RecentFiles.clear() }
                }
            }
            .disabled(queue.isRunning)

            Divider()

            Button("Clear Queue") { queue.clear() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(queue.isEmpty || queue.isRunning)

            Button("Reveal in Finder") { reveal() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(revealURLs.isEmpty)
        }

        CommandMenu("Track") {
            Button("Recognize") { queue.run() }
                .keyboardShortcut("r")
                .disabled(!queue.canRun)

            Button("Cancel Recognition") { queue.cancel() }
                .keyboardShortcut(".")
                .disabled(!queue.isRunning)

            Divider()

            Button("Include All Tracks") { queue.includeAll() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(queue.isEmpty || queue.isRunning)

            Button("Include No Tracks") { queue.includeNone() }
                .keyboardShortcut("d", modifiers: [.command, .option])
                .disabled(queue.isEmpty || queue.isRunning)
        }

        CommandGroup(after: .sidebar) {
            Button(ui.isInspectorPresented ? "Hide Inspector" : "Show Inspector") {
                ui.isInspectorPresented.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Toggle("Needs Review Only", isOn: Binding(
                get: { ui.showNeedsReviewOnly },
                set: { ui.showNeedsReviewOnly = $0 }
            ))
            .keyboardShortcut("e", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .help) {
            Link("macSubtitleOCR Help", destination: URL(string: "https://jeffalldridge.github.io/macSubtitleOCR-gui/")!)
            Link("Report an Issue…", destination: URL(string: "https://github.com/jeffalldridge/macSubtitleOCR-gui/issues/new/choose")!)
            Divider()
            Button("Acknowledgements") { openWindow(id: AcknowledgementsView.windowID) }
        }
    }

    private var revealURLs: [URL] {
        if let track = queue.selectedTrack, let output = track.outputURL { return [output] }
        if let file = queue.selectedFile { return [file.url] }
        return []
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(revealURLs)
    }
}

/// The standard About panel with credits for the upstream engine.
enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6

        func append(_ text: String, link: String? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [.font: body, .paragraphStyle: paragraph,
                                                             .foregroundColor: NSColor.labelColor]
            if let link { attributes[.link] = link }
            credits.append(NSAttributedString(string: text, attributes: attributes))
        }

        append("Bitmap subtitles in, clean SRT out.\n\n")
        append("Text recognition engine derived from ")
        append("macSubtitleOCR", link: "https://github.com/ecdye/macSubtitleOCR")
        append(" by Ethan Dye (MIT License).\n")
        append("Recognition by Apple’s Vision framework.\n\n")
        append("Help & FAQ", link: "https://jeffalldridge.github.io/macSubtitleOCR-gui/")
        append("  ·  ")
        append("Source on GitHub", link: "https://github.com/jeffalldridge/macSubtitleOCR-gui")

        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "macSubtitleOCR",
        ])
    }
}

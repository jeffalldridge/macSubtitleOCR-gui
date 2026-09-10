import SwiftUI
import TipKit

/// Real entry point so `--self-check` and `--version` can run headlessly.
@main
enum EntryPoint {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--self-check") {
            exit(SelfCheck.run())
        }
        if arguments.contains("--version") {
            print(SelfCheck.versionString)
            exit(0)
        }
        MacSubtitleOCRApp.main()
    }
}

struct MacSubtitleOCRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var settings: AppSettings
    @State private var queue: ConversionQueue
    @State private var ui = AppUIState()
    @State private var updates = UpdateChecker()

    init() {
        let settings = AppSettings()
        let queue = ConversionQueue(settings: settings)
        _settings = State(initialValue: settings)
        _queue = State(initialValue: queue)
        AppDelegate.queue = queue
        try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
    }

    var body: some Scene {
        Window("macSubtitleOCR", id: MainWindow.windowID) {
            MainWindow()
                .environment(settings)
                .environment(queue)
                .environment(ui)
                .environment(updates)
                .task {
                    queue.cache.prune()
                    await updates.checkIfDue(settings: settings)
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 680)
        // The main window must always open. Scene restoration can decide
        // otherwise from a stale record — a bundle that once ran a different
        // scene structure, for instance, as every install upgraded from 0.2
        // has — and the app would then launch to nothing at all. This app has
        // one main window and no documents, so there is nothing to restore.
        .restorationBehavior(.disabled)
        // Present the main window at launch, always. Without this, a stale
        // per-app record can leave the app running with no window at all —
        // an app that looks like it failed to open.
        .defaultLaunchBehavior(.presented)
        .commands {
            AppCommands(queue: queue, ui: ui, settings: settings, updates: updates)
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(queue)
                .environment(updates)
        }

        Window("Acknowledgements", id: AcknowledgementsView.windowID) {
            AcknowledgementsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 560, height: 640)
        .restorationBehavior(.disabled)
    }
}

/// Window-level UI state that menu commands need to reach.
@Observable
final class AppUIState {
    var isInspectorPresented = false
    var showNeedsReviewOnly = false
}

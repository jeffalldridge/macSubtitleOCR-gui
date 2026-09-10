import Foundation

/// All interactive entry points resolve the output destination before starting.
enum RunAction {
    static func start(queue: ConversionQueue, settings: AppSettings) {
        guard queue.canRun else { return }
        if settings.outputDestination.asksBeforeRunning {
            guard let folder = FileImport.presentFolderPanel() else { return }
            queue.runOptions.outputFolder = folder
        } else {
            queue.runOptions.outputFolder = settings.outputDestination.resolvedFolder
        }
        queue.run()
    }
}

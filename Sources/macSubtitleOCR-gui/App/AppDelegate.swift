import AppKit
import UserNotifications

/// Finder integration (Open With, Dock drops, Services), quit confirmation
/// while a run is active, and notification delivery.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the App before any window exists.
    static var queue: ConversionQueue?

    /// URLs handed to us before the queue was ready.
    private var pendingURLs: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServicesProvider()
        // The notification centre is deliberately not touched here.
        // `UNUserNotificationCenter.current()` raises
        // NSInternalInconsistencyException ("bundleProxyForCurrentProcess is
        // nil") when the process is not a real `.app`, which is exactly what
        // `swift run` produces during development. Notifier attaches this
        // delegate the first time a notification is actually posted.
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        flushPendingURLs()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let expanded = urls.flatMap(FileImport.expand)
        guard let queue = Self.queue else {
            pendingURLs.append(contentsOf: expanded)
            return
        }
        queue.add(urls: expanded)
        NSApp.activate()
    }

    private func flushPendingURLs() {
        guard !pendingURLs.isEmpty, let queue = Self.queue else { return }
        queue.add(urls: pendingURLs)
        pendingURLs.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let queue = Self.queue, queue.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Recognition is still running."
        alert.informativeText = "Quitting now stops the run. Subtitle files that were already saved are kept."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep Running")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            queue.cancel()
            return .terminateNow
        }
        return .terminateCancel
    }

    // MARK: - Notifications

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        NSApp.activate()
    }
}

/// The Finder Services menu entry. Declared in Info.plist under `NSServices`.
final class ServicesProvider: NSObject {
    @objc func recognizeSubtitles(_ pasteboard: NSPasteboard,
                                  userData: String,
                                  error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        let expanded = urls.flatMap(FileImport.expand)
        guard !expanded.isEmpty else {
            error.pointee = "None of the selected files are MKV, MKS, SUP, SUB, or IDX files."
            return
        }
        AppDelegate.queue?.add(urls: expanded)
        NSApp.activate()
    }
}

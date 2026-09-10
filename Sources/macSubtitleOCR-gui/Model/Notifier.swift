import AppKit
import UserNotifications

/// Completion notices when the app is in the background, and Dock progress.
enum Notifier {
    static func runFinished(_ summary: ConversionQueue.RunSummary, settings: AppSettings) {
        guard settings.notifyWhenDone, !NSApp.isActive else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            let content = UNMutableNotificationContent()
            content.title = "Recognition complete"
            content.body = [summary.headline, summary.detail].compactMap { $0 }.joined(separator: " · ")
            content.sound = .default
            let request = UNNotificationRequest(identifier: "run-finished-\(UUID().uuidString)",
                                                content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}

/// A progress bar on the Dock icon while a run is active.
enum DockProgress {
    private static var indicator: NSProgressIndicator?

    static func update(_ fraction: Double) {
        let tile = NSApp.dockTile
        if indicator == nil {
            let size = tile.size
            let container = NSImageView(frame: NSRect(origin: .zero, size: size))
            container.image = NSApp.applicationIconImage
            let bar = NSProgressIndicator(frame: NSRect(x: size.width * 0.12, y: size.height * 0.08,
                                                        width: size.width * 0.76, height: 14))
            bar.style = .bar
            bar.isIndeterminate = false
            bar.minValue = 0
            bar.maxValue = 1
            container.addSubview(bar)
            tile.contentView = container
            indicator = bar
        }
        indicator?.doubleValue = fraction
        tile.display()
    }

    static func hide() {
        NSApp.dockTile.contentView = nil
        indicator = nil
        NSApp.dockTile.display()
    }
}

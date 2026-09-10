import AppKit
import Foundation

/// File ▸ Open Recent and the Dock menu, backed by the system's list.
enum RecentFiles {
    static func note(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    static var urls: [URL] {
        NSDocumentController.shared.recentDocumentURLs
    }

    static func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
}

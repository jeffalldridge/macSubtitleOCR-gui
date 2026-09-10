import CryptoKit
import Foundation
import SubtitleEngine

/// Extracted MKV tracks on disk, so reopening a file is instant.
///
/// Lives in `~/Library/Caches/<bundle id>/streams`, which Time Machine
/// skips and the system may purge. Keys cover the file's path, size,
/// modification date, and track number.
nonisolated struct StreamCache: Sendable {
    let directory: URL

    static let defaultMaxBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let defaultMaxAge: TimeInterval = 14 * 24 * 3600

    static var `default`: StreamCache {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tentstudios.macSubtitleOCR-gui"
        return StreamCache(directory: base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("streams", isDirectory: true))
    }

    init(directory: URL) {
        self.directory = directory
    }

    /// A stable key for one track of one file version.
    static func key(for url: URL, track: TrackInfo) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let material = "\(url.standardizedFileURL.path)|\(size)|\(modified)|\(track.id)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// URLs for a cached track, or nil when it is not cached.
    func cachedURLs(for key: String, format: BitmapSubtitleFormat) -> (primary: URL, idx: URL?)? {
        let fm = FileManager.default
        switch format {
        case .pgs:
            let url = directory.appendingPathComponent("\(key).sup")
            return fm.fileExists(atPath: url.path) ? (url, nil) : nil
        case .vobsub:
            let sub = directory.appendingPathComponent("\(key).sub")
            let idx = directory.appendingPathComponent("\(key).idx")
            return fm.fileExists(atPath: sub.path) && fm.fileExists(atPath: idx.path) ? (sub, idx) : nil
        }
    }

    /// Write an extracted track and return where it went.
    ///
    /// Prunes afterwards, so the cache stays bounded within a long session
    /// rather than only across launches.
    @discardableResult
    func store(_ extracted: ExtractedTrack, key: String) throws -> (primary: URL, idx: URL?) {
        defer { prune() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        switch extracted {
        case .pgs(let data):
            let url = directory.appendingPathComponent("\(key).sup")
            try data.write(to: url, options: .atomic)
            return (url, nil)
        case .vobsub(let sub, let idx):
            let subURL = directory.appendingPathComponent("\(key).sub")
            let idxURL = directory.appendingPathComponent("\(key).idx")
            try sub.write(to: subURL, options: .atomic)
            try idx.write(to: idxURL, atomically: true, encoding: .utf8)
            return (subURL, idxURL)
        }
    }

    /// Open a cached track as a stream.
    func loadStream(key: String, format: BitmapSubtitleFormat) throws -> (any SubtitleStream)? {
        guard let urls = cachedURLs(for: key, format: format) else { return nil }
        // Touch so pruning treats it as recently used.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: urls.primary.path)
        switch format {
        case .pgs:
            return try PGSStream(url: urls.primary)
        case .vobsub:
            guard let idx = urls.idx else { return nil }
            return try VobSubStream(subURL: urls.primary, idxURL: idx)
        }
    }

    /// Drop old entries and keep the total under `maxBytes`, oldest first.
    func prune(maxBytes: Int64 = StreamCache.defaultMaxBytes, maxAge: TimeInterval = StreamCache.defaultMaxAge) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        struct Entry { let url: URL; let size: Int64; let modified: Date }

        var items: [Entry] = entries.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return Entry(url: url, size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? .distantPast)
        }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for item in items where item.modified < cutoff {
            try? fm.removeItem(at: item.url)
        }
        items.removeAll { $0.modified < cutoff }

        // Evict by cache key, not by file: a VobSub entry is a .sub and a .idx,
        // and deleting one leaves the other orphaned and unusable while still
        // counting toward the total.
        var byKey: [String: [Entry]] = [:]
        for item in items {
            byKey[item.url.deletingPathExtension().lastPathComponent, default: []].append(item)
        }
        var groups = byKey.values.map { entries in
            (size: entries.reduce(0) { $0 + $1.size },
             modified: entries.map(\.modified).max() ?? .distantPast,
             urls: entries.map(\.url))
        }
        groups.sort { $0.modified < $1.modified }

        var total = groups.reduce(0) { $0 + $1.size }
        for group in groups where total > maxBytes {
            for url in group.urls { try? fm.removeItem(at: url) }
            total -= group.size
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    var totalBytes: Int64 {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return entries.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

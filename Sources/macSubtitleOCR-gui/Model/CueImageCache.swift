import CoreGraphics
import Foundation
import SubtitleEngine

/// Decoded cue images for the review list and preview, decoded off the main
/// actor and kept in an `NSCache`.
final class CueImageCache {
    static let shared = CueImageCache()

    private let cache = NSCache<NSString, CGImage>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    init() {
        cache.countLimit = 400
    }

    func image(for track: QueueTrack, index: Int, style: IndexedBitmap.RenderStyle = .display) async -> CGImage? {
        guard let stream = track.stream else { return nil }
        let key = "\(track.id.uuidString)/\(index)/\(style)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        if let running = inFlight[key as String] { return await running.value }

        let task = Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let bitmap = try? stream.bitmap(at: index) else { return nil }
            return bitmap.cgImage(style: style, cropToContent: true, margin: style == .display ? 0 : 12)
        }
        inFlight[key as String] = task
        let image = await task.value
        inFlight[key as String] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

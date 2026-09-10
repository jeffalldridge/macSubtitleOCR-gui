import Foundation

/// Rules for turning decoded cue timings into SRT end times.
///
/// PGS streams carry real end times (the clear display set). VobSub often
/// says "until the next subpicture" instead. The rules:
/// - A known end is kept, clamped so it does not overlap the next cue.
/// - An unknown end becomes `min(next start − gap, start + defaultDuration)`.
/// - Every cue keeps a positive duration.
public enum SRTTiming {
    public static let defaultDuration: TimeInterval = 5
    public static let gap: TimeInterval = 0.1
    public static let minimumDuration: TimeInterval = 0.05

    public static func resolveEnds(starts: [TimeInterval], ends: [TimeInterval?]) -> [TimeInterval] {
        precondition(starts.count == ends.count)
        var resolved: [TimeInterval] = []
        resolved.reserveCapacity(starts.count)

        /// Nonsense from the file becomes a usable number rather than
        /// spreading through every later calculation.
        func sane(_ time: TimeInterval?) -> TimeInterval? {
            guard let time, time.isFinite else { return nil }
            return min(max(time, 0), SRTFile.maxTime)
        }

        for i in starts.indices {
            let start = sane(starts[i]) ?? 0
            let nextStart = i + 1 < starts.count ? sane(starts[i + 1]) : nil
            var end: TimeInterval

            if let known = sane(ends[i]), known > start {
                end = known
                if let nextStart, end > nextStart { end = nextStart }
            } else {
                end = start + defaultDuration
                if let nextStart { end = min(end, nextStart - gap) }
                if let known = sane(ends[i]), known <= start, let nextStart {
                    // A broken end: fall back to the next cue's start.
                    end = min(nextStart, start + defaultDuration)
                }
            }

            if end <= start { end = start + minimumDuration }
            resolved.append(end)
        }
        return resolved
    }
}

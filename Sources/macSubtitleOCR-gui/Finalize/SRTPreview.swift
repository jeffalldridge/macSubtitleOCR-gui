import Foundation

public struct SRTPreviewCue: Sendable, Hashable {
    public let index: Int
    public let timing: String
    public let text: String
}

public struct SRTPreview: Sendable {
    public let cues: [SRTPreviewCue]
    public let totalCount: Int

    public init(cues: [SRTPreviewCue], totalCount: Int) {
        self.cues = cues
        self.totalCount = totalCount
    }

    public static let empty = SRTPreview(cues: [], totalCount: 0)
}

public enum SRTPreviewLoader {
    /// Read up to `maxCues` cues from the start of an SRT file. Also returns
    /// the total cue count (best-effort: counts blank-line separated blocks).
    public static func load(_ url: URL, maxCues: Int = 4) throws -> SRTPreview {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return parse(raw, maxCues: maxCues)
    }

    static func parse(_ raw: String, maxCues: Int) -> SRTPreview {
        // Normalize CRLF and split on blank-line cue separators. SRT cues are:
        //   <index>
        //   HH:MM:SS,mmm --> HH:MM:SS,mmm
        //   <text lines…>
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.split(separator: "\n\n", omittingEmptySubsequences: true)
        var cues: [SRTPreviewCue] = []
        var total = 0

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 2,
                  let timingLine = lines.first(where: { $0.contains("-->") }),
                  let timingIdx = lines.firstIndex(of: timingLine) else {
                continue
            }
            total += 1
            if cues.count >= maxCues { continue }

            let indexValue = Int(lines.first ?? "") ?? (cues.count + 1)
            let textLines = Array(lines.dropFirst(timingIdx + 1))
            let text = textLines.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            cues.append(SRTPreviewCue(
                index: indexValue,
                timing: shortTiming(from: timingLine),
                text: text
            ))
        }
        return SRTPreview(cues: cues, totalCount: total)
    }

    /// Trim a timing line down to "MM:SS → MM:SS" for display. Falls back to
    /// the raw line if the format is unexpected.
    private static func shortTiming(from line: String) -> String {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return line.trimmingCharacters(in: .whitespaces) }
        let start = compactTimestamp(parts[0])
        let end = compactTimestamp(parts[1])
        return "\(start) → \(end)"
    }

    private static func compactTimestamp(_ raw: String) -> String {
        // "00:01:47,250" -> "01:47" ;  "01:23:45,000" -> "1:23:45"
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let timeOnly = trimmed.split(separator: ",").first.map(String.init) ?? trimmed
        let pieces = timeOnly.split(separator: ":").map(String.init)
        guard pieces.count == 3, let h = Int(pieces[0]) else { return timeOnly }
        if h == 0 { return "\(pieces[1]):\(pieces[2])" }
        return "\(h):\(pieces[1]):\(pieces[2])"
    }
}

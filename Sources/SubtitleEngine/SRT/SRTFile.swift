import Foundation

/// SubRip (.srt) rendering and parsing.
public enum SRTFile {
    /// `HH:MM:SS,mmm`
    public static func timestamp(_ time: TimeInterval) -> String {
        let totalMilliseconds = max(0, Int((time * 1000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds / 60_000) % 60
        let seconds = (totalMilliseconds / 1000) % 60
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    /// Parses `HH:MM:SS,mmm` (a period is accepted for the milliseconds separator).
    public static func parseTimestamp(_ text: String) -> TimeInterval? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ",")
        let mainAndMillis = cleaned.split(separator: ",", omittingEmptySubsequences: false)
        guard mainAndMillis.count == 2,
              let millis = Int(mainAndMillis[1].prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0)) else {
            return nil
        }
        let parts = mainAndMillis[0].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2]) + TimeInterval(millis) / 1000
    }

    public static func render(_ cues: [SRTCue]) -> String {
        var out = ""
        out.reserveCapacity(cues.count * 64)
        for cue in cues {
            out += "\(cue.index)\n"
            out += "\(timestamp(cue.start)) --> \(timestamp(cue.end))\n"
            out += cue.text
            out += "\n\n"
        }
        return out
    }

    /// Lenient parser: tolerates CRLF, a BOM, missing index lines, and extra
    /// blank lines. Cues without a timing line are skipped.
    public static func parse(_ text: String) -> [SRTCue] {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }

        var cues: [SRTCue] = []
        var block: [String] = []

        func flush() {
            defer { block.removeAll() }
            guard let timingLine = block.firstIndex(where: { $0.contains("-->") }) else { return }
            let pieces = block[timingLine].components(separatedBy: "-->")
            guard pieces.count == 2,
                  let start = parseTimestamp(pieces[0]),
                  let end = parseTimestamp(String(pieces[1].split(separator: " ").first ?? "")) else { return }
            let index = timingLine > 0 ? Int(block[timingLine - 1].trimmingCharacters(in: .whitespaces)) : nil
            let textLines = block[(timingLine + 1)...]
            cues.append(SRTCue(index: index ?? cues.count + 1,
                               start: start,
                               end: end,
                               text: textLines.joined(separator: "\n")))
        }

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                block.append(String(line))
            }
        }
        flush()
        return cues
    }
}

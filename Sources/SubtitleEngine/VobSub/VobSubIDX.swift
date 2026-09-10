import Foundation

/// The text side of a VobSub pair: the master palette, language, and the
/// timestamp / byte-offset of every subpicture in the `.sub` file.
struct VobSubIDX: Sendable {
    struct Entry: Sendable, Equatable {
        let timestamp: TimeInterval
        let offset: Int
    }

    /// 16 RGB triplets (48 bytes).
    let palette: [UInt8]
    let language: String?
    let entries: [Entry]

    /// The palette used when an `.idx` has none (mkvmerge's default).
    static let defaultPalette: [UInt8] = [
        0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00,
        0xFF, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0x80, 0x80, 0x00, 0x80, 0x80, 0xFF, 0x80, 0x00, 0x80, 0x80, 0xFF, 0x80,
        0x00, 0x80, 0x80, 0xFF, 0x80, 0x80, 0x55, 0x55, 0x55, 0xAA, 0xAA, 0xAA,
    ]

    init(url: URL) throws {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) { throw EngineError.fileNotFound(url) }
            // Some tools write Latin-1.
            guard let fallback = try? String(contentsOf: url, encoding: .isoLatin1) else { throw error }
            text = fallback
        }
        try self.init(text: text)
    }

    init(text: String) throws {
        var palette: [UInt8] = []
        var language: String?
        var entries: [Entry] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("palette:") {
                palette = Self.parsePalette(String(line.dropFirst("palette:".count)))
            } else if line.hasPrefix("id:") {
                // "id: en, index: 0"
                let value = line.dropFirst("id:".count).split(separator: ",").first.map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if let value, !value.isEmpty, language == nil { language = value }
            } else if line.hasPrefix("timestamp:") {
                guard let entry = Self.parseTimestampLine(line) else { continue }
                entries.append(entry)
            }
        }

        self.palette = palette.count == 48 ? palette : Self.defaultPalette
        self.language = language
        self.entries = entries
    }

    private static func parsePalette(_ text: String) -> [UInt8] {
        text.split(separator: ",").flatMap { piece -> [UInt8] in
            let hex = piece.trimmingCharacters(in: .whitespaces)
            guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return [] }
            return [UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        }
    }

    /// "timestamp: 00:01:47:250, filepos: 000001800"
    private static func parseTimestampLine(_ line: String) -> Entry? {
        let parts = line.split(separator: ",")
        guard parts.count >= 2 else { return nil }
        let time = parts[0].dropFirst("timestamp:".count).trimmingCharacters(in: .whitespaces)
        guard let posRange = parts[1].range(of: "filepos:") else { return nil }
        let pos = parts[1][posRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let offset = Int(pos, radix: 16) else { return nil }

        // `Double("inf")` and `Double("nan")` both parse, and an infinite cue
        // time propagates all the way to a trap when the SRT is written.
        let pieces = time.split(separator: ":").compactMap { Double($0) }
        guard pieces.count == 4, pieces.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let seconds = pieces[0] * 3600 + pieces[1] * 60 + pieces[2] + pieces[3] / 1000
        guard seconds.isFinite, seconds >= 0, offset >= 0 else { return nil }
        return Entry(timestamp: seconds, offset: offset)
    }
}

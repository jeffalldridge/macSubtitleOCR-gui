import Foundation
import os

/// Reads Matroska containers from a memory-mapped buffer.
///
/// `probe()` reads only the `Info` and `Tracks` elements, so it returns in
/// milliseconds regardless of file size. `extract(trackNumber:)` walks the
/// clusters once and gathers the blocks of one track.
public struct MKVReader: Sendable {
    public let url: URL
    let data: Data

    static let logger = Logger(subsystem: "com.tentstudios.macSubtitleOCR", category: "engine.mkv")

    /// Nanoseconds per timestamp tick. One second per tick is already absurd;
    /// beyond it the presentation-time arithmetic would overflow.
    static let maxTimestampScale: UInt64 = 1_000_000_000
    /// Matroska track numbers are small. This is generous and keeps the value
    /// representable.
    static let maxTrackNumber = 1_000_000

    public init(url: URL) throws {
        let data = try Data.mapped(contentsOf: url)
        try self.init(data: data, url: url)
    }

    /// For tests and in-memory containers.
    init(data: Data, url: URL) throws {
        self.url = url
        self.data = data
        let looksMatroska = data.withUnsafeBytes { bytes -> Bool in
            let reader = EBMLReader(bytes: bytes)
            guard let header = reader.element(at: 0), header.id == MatroskaID.ebmlHeader else { return false }
            var docType: String?
            reader.forEachChild(of: header) { child in
                if child.id == MatroskaID.docType { docType = reader.string(child) }
                return docType == nil
            }
            // Accept "matroska" and "webm"; a missing DocType is tolerated.
            return docType == nil || docType == "matroska" || docType == "webm"
        }
        guard looksMatroska else { throw EngineError.notMatroska(url) }
    }

    // MARK: - Probe

    public func probe() throws -> ContainerInfo {
        try data.withUnsafeBytes { bytes in
            let reader = EBMLReader(bytes: bytes)
            guard let segment = Self.segment(in: reader) else { throw EngineError.notMatroska(url) }

            var timestampScale: UInt64 = 1_000_000
            var durationUnits: Double?
            var title: String?
            var tracksElement: EBMLReader.Element?
            var sawInfo = false

            reader.forEachChild(of: segment) { child in
                switch child.id {
                case MatroskaID.info:
                    reader.forEachChild(of: child) { field in
                        switch field.id {
                        case MatroskaID.timestampScale:
                            // Matroska's scale is nanoseconds per tick. Zero
                            // would make every timestamp zero; an enormous
                            // value would overflow the PTS arithmetic later.
                            if let value = reader.uint(field), (1...Self.maxTimestampScale).contains(value) {
                                timestampScale = value
                            }
                        case MatroskaID.duration:
                            durationUnits = reader.float(field).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                        case MatroskaID.title:
                            title = reader.string(field)
                        default:
                            break
                        }
                        return true
                    }
                    sawInfo = true
                case MatroskaID.tracks:
                    tracksElement = child
                default:
                    break
                }
                // Neither element's position is fixed: Tracks can follow the
                // first Cluster, and Info can follow Tracks. Keep walking
                // until both are in hand.
                return tracksElement == nil || !sawInfo
            }

            guard let tracksElement else { throw EngineError.noTracksElement }

            var tracks: [TrackInfo] = []
            var otherCodecs: [String] = []
            reader.forEachChild(of: tracksElement) { entry in
                guard entry.id == MatroskaID.trackEntry else { return true }
                if let parsed = Self.parseTrackEntry(entry, reader: reader) {
                    switch parsed {
                    case .bitmap(let info): tracks.append(info)
                    case .otherSubtitle(let codec): otherCodecs.append(codec)
                    }
                }
                return true
            }

            let duration = durationUnits.map { $0 * Double(timestampScale) / 1_000_000_000 }
            return ContainerInfo(tracks: tracks.sorted { $0.id < $1.id },
                                 otherSubtitleCodecs: otherCodecs,
                                 duration: duration,
                                 title: title,
                                 timestampScale: timestampScale)
        }
    }

    // MARK: - Helpers

    static func segment(in reader: EBMLReader) -> EBMLReader.Element? {
        guard let header = reader.element(at: 0), header.id == MatroskaID.ebmlHeader else { return nil }
        var offset = header.endOffset
        // Skip anything (Void, CRC) between the header and the Segment.
        while let element = reader.element(at: offset) {
            if element.id == MatroskaID.segment { return element }
            guard element.endOffset > offset else { return nil }
            offset = element.endOffset
        }
        return nil
    }

    enum ParsedTrack {
        case bitmap(TrackInfo)
        case otherSubtitle(codecID: String)
    }

    static func parseTrackEntry(_ entry: EBMLReader.Element, reader: EBMLReader) -> ParsedTrack? {
        var number: UInt64?
        var type: UInt64?
        var codecID: String?
        var language: String?
        var languageBCP47: String?
        var name: String?
        var isDefault = true   // Matroska default for FlagDefault is 1
        var isForced = false
        var codecPrivate: Data?

        reader.forEachChild(of: entry) { field in
            switch field.id {
            case MatroskaID.trackNumber: number = reader.uint(field)
            case MatroskaID.trackType: type = reader.uint(field)
            case MatroskaID.codecID: codecID = reader.string(field)
            case MatroskaID.language: language = reader.string(field)
            case MatroskaID.languageBCP47: languageBCP47 = reader.string(field)
            case MatroskaID.name: name = reader.string(field)
            case MatroskaID.flagDefault: isDefault = (reader.uint(field) ?? 1) != 0
            case MatroskaID.flagForced: isForced = (reader.uint(field) ?? 0) != 0
            case MatroskaID.codecPrivate: codecPrivate = reader.data(field)
            default: break
            }
            return true
        }

        guard let number, let codecID, type == MatroskaID.TrackType.subtitle else { return nil }
        // Track numbers are a VINT, so a crafted file can declare one that no
        // Int can hold. Matroska's own limit is far below this.
        guard number >= 1, number <= UInt64(Self.maxTrackNumber) else { return nil }
        guard let format = BitmapSubtitleFormat(codecID: codecID) else {
            return .otherSubtitle(codecID: codecID)
        }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .bitmap(TrackInfo(id: Int(number),
                                 format: format,
                                 codecID: codecID,
                                 language: language?.isEmpty == false ? language : nil,
                                 languageBCP47: languageBCP47?.isEmpty == false ? languageBCP47 : nil,
                                 name: trimmedName?.isEmpty == false ? trimmedName : nil,
                                 isDefault: isDefault,
                                 isForced: isForced,
                                 codecPrivate: codecPrivate))
    }
}

import Foundation

/// Assembles tiny Matroska files for tests. Element IDs are given with their
/// marker bits, exactly as they appear in the spec (e.g. `0x1A45DFA3`).
enum EBMLBuilder {
    static func idBytes(_ id: UInt32) -> [UInt8] {
        var bytes: [UInt8] = []
        var value = id
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return bytes.isEmpty ? [0] : bytes
    }

    /// Shortest VINT encoding of a size.
    static func sizeBytes(_ size: Int) -> [UInt8] {
        var length = 1
        while size >= (1 << (7 * length)) - 1 { length += 1 }
        var bytes = [UInt8](repeating: 0, count: length)
        var value = UInt64(size)
        for i in stride(from: length - 1, through: 0, by: -1) {
            bytes[i] = UInt8(value & 0xFF)
            value >>= 8
        }
        bytes[0] |= UInt8(0x80 >> (length - 1))
        return bytes
    }

    /// The 8-byte "unknown size" marker.
    static let unknownSize: [UInt8] = [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]

    static func element(_ id: UInt32, _ payload: [UInt8]) -> [UInt8] {
        idBytes(id) + sizeBytes(payload.count) + payload
    }

    static func element(_ id: UInt32, _ children: [[UInt8]]) -> [UInt8] {
        element(id, children.flatMap { $0 })
    }

    static func unknownSizeElement(_ id: UInt32, _ children: [[UInt8]]) -> [UInt8] {
        idBytes(id) + unknownSize + children.flatMap { $0 }
    }

    static func uint(_ id: UInt32, _ value: UInt64) -> [UInt8] {
        var bytes: [UInt8] = []
        var v = value
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v > 0
        return element(id, bytes)
    }

    static func string(_ id: UInt32, _ text: String) -> [UInt8] {
        element(id, Array(text.utf8))
    }

    static func float(_ id: UInt32, _ value: Double) -> [UInt8] {
        var bits = value.bitPattern.bigEndian
        let bytes = withUnsafeBytes(of: &bits) { Array($0) }
        return element(id, bytes)
    }

    static func binary(_ id: UInt32, _ bytes: [UInt8]) -> [UInt8] {
        element(id, bytes)
    }

    /// A standard EBML header declaring a Matroska document.
    static func matroskaHeader() -> [UInt8] {
        element(0x1A45_DFA3, [
            uint(0x4286, 1),          // EBMLVersion
            uint(0x42F7, 1),          // EBMLReadVersion
            uint(0x42F2, 4),          // EBMLMaxIDLength
            uint(0x42F3, 8),          // EBMLMaxSizeLength
            string(0x4282, "matroska"),
            uint(0x4287, 4),          // DocTypeVersion
            uint(0x4285, 2),          // DocTypeReadVersion
        ])
    }

    /// A subtitle TrackEntry. `extra` children are appended verbatim.
    static func subtitleTrack(number: UInt64,
                              codec: String,
                              language: String? = "eng",
                              name: String? = nil,
                              isDefault: Bool? = nil,
                              isForced: Bool? = nil,
                              codecPrivate: [UInt8]? = nil,
                              extra: [[UInt8]] = []) -> [UInt8] {
        var children: [[UInt8]] = [
            uint(0xD7, number),
            uint(0x73C5, number * 1000),
            uint(0x83, 17),
            string(0x86, codec),
        ]
        if let language { children.append(string(0x22B5_9C, language)) }
        if let name { children.append(string(0x536E, name)) }
        if let isDefault { children.append(uint(0x88, isDefault ? 1 : 0)) }
        if let isForced { children.append(uint(0x55AA, isForced ? 1 : 0)) }
        if let codecPrivate { children.append(binary(0x63A2, codecPrivate)) }
        children.append(contentsOf: extra)
        return element(0xAE, children)
    }

    /// A SimpleBlock for `track` at `relativeTimestamp` with `payload`.
    static func simpleBlock(track: UInt8, relativeTimestamp: Int16, flags: UInt8 = 0x80, payload: [UInt8]) -> [UInt8] {
        let ts = UInt16(bitPattern: relativeTimestamp)
        let body: [UInt8] = [0x80 | track, UInt8(ts >> 8), UInt8(ts & 0xFF), flags] + payload
        return element(0xA3, body)
    }

    static func cluster(timestamp: UInt64, blocks: [[UInt8]], unknownSize: Bool = false) -> [UInt8] {
        let children = [uint(0xE7, timestamp)] + blocks
        return unknownSize ? unknownSizeElement(0x1F43_B675, children) : element(0x1F43_B675, children)
    }

    static func segment(_ children: [[UInt8]], unknownSize: Bool = false) -> [UInt8] {
        unknownSize ? unknownSizeElement(0x1853_8067, children) : element(0x1853_8067, children)
    }

    static func file(_ segmentChildren: [[UInt8]], unknownSizeSegment: Bool = false) -> Data {
        Data(matroskaHeader() + segment(segmentChildren, unknownSize: unknownSizeSegment))
    }

    static func info(timestampScale: UInt64 = 1_000_000, duration: Double? = nil, title: String? = nil) -> [UInt8] {
        var children: [[UInt8]] = [uint(0x2AD7_B1, timestampScale)]
        if let duration { children.append(float(0x4489, duration)) }
        if let title { children.append(string(0x7BA9, title)) }
        return element(0x1549_A966, children)
    }

    static func tracks(_ entries: [[UInt8]]) -> [UInt8] {
        element(0x1654_AE6B, entries)
    }

    /// Write to a temporary file and return its URL.
    static func write(_ data: Data, name: String = "synthetic.mkv") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubtitleEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

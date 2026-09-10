import Foundation

/// Decodes EBML variable-length integers and element headers from a buffer.
///
/// Works on a raw buffer (typically a memory-mapped file) so that walking a
/// multi-gigabyte remux is pointer arithmetic rather than one syscall per
/// byte.
struct EBMLReader {
    let bytes: UnsafeRawBufferPointer

    struct VINT: Equatable {
        let value: UInt64
        let length: Int
        /// True when every data bit is set — the "unknown size" marker.
        let isAllOnes: Bool
    }

    struct Element: Equatable {
        let id: UInt32
        /// Declared size, or nil for an unknown-size element.
        let size: UInt64?
        let dataOffset: Int
        /// End of the element's data, clamped to the buffer. For unknown-size
        /// elements this is the end of the buffer; callers walk children to
        /// find the real end.
        let endOffset: Int

        var dataRange: Range<Int> { dataOffset..<endOffset }
        var isUnknownSize: Bool { size == nil }
    }

    init(bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
    }

    /// Read a VINT at `offset`. Element IDs keep their marker bit
    /// (`stripMarker: false`); sizes drop it (`stripMarker: true`).
    func readVINT(at offset: Int, stripMarker: Bool) -> VINT? {
        guard offset >= 0, offset < bytes.count else { return nil }
        let first = bytes[offset]
        guard first != 0 else { return nil } // would be > 8 bytes: invalid

        var length = 1
        var mask: UInt8 = 0x80
        while first & mask == 0 {
            length += 1
            mask >>= 1
        }
        guard offset + length <= bytes.count else { return nil }

        var value = UInt64(first)
        var dataBits = UInt64(first & ~mask)
        for i in 1..<length {
            let byte = UInt64(bytes[offset + i])
            value = (value << 8) | byte
            dataBits = (dataBits << 8) | byte
        }
        let allOnes = dataBits == (UInt64(1) << UInt64(7 * length)) - 1
        return VINT(value: stripMarker ? dataBits : value, length: length, isAllOnes: allOnes)
    }

    /// Parse an element header at `offset`.
    ///
    /// `limit` bounds the element's data. Passing a parent's end means a
    /// child can never claim bytes beyond it, however large a size it
    /// declares — a `Tracks` element of ten bytes cannot contain a
    /// `TrackEntry` that reads a megabyte of unrelated file.
    func element(at offset: Int, limit: Int? = nil) -> Element? {
        guard let id = readVINT(at: offset, stripMarker: false), id.length <= 4 else { return nil }
        guard let size = readVINT(at: offset + id.length, stripMarker: true) else { return nil }
        let dataOffset = offset + id.length + size.length
        let ceiling = min(limit ?? bytes.count, bytes.count)
        guard dataOffset <= ceiling else { return nil }

        if size.isAllOnes {
            return Element(id: UInt32(id.value), size: nil, dataOffset: dataOffset, endOffset: ceiling)
        }
        let end = min(UInt64(ceiling), UInt64(dataOffset) &+ size.value)
        return Element(id: UInt32(id.value), size: size.value, dataOffset: dataOffset, endOffset: Int(end))
    }

    // MARK: - Scalar payloads

    func uint(_ element: Element) -> UInt64? {
        let length = element.endOffset - element.dataOffset
        guard length > 0 else { return 0 } // zero-length integer means 0
        return bytes.readUIntBE(at: element.dataOffset, length: length)
    }

    func float(_ element: Element) -> Double? {
        switch element.endOffset - element.dataOffset {
        case 4:
            return bytes.readUInt32BE(at: element.dataOffset).map { Double(Float(bitPattern: $0)) }
        case 8:
            return bytes.readUIntBE(at: element.dataOffset, length: 8).map { Double(bitPattern: $0) }
        case 0:
            return 0
        default:
            return nil
        }
    }

    /// UTF-8 string with trailing NUL padding removed.
    func string(_ element: Element) -> String? {
        guard let data = bytes.slice(element.dataRange) else { return nil }
        let trimmed = data.prefix { $0 != 0 }
        return String(data: Data(trimmed), encoding: .utf8)
    }

    func data(_ element: Element) -> Data? {
        bytes.slice(element.dataRange)
    }

    // MARK: - Iteration

    /// Visit the children of `parent` in order. The visitor returns `false`
    /// to stop early.
    ///
    /// Unknown-size elements (live-muxed files, some remuxers) are handled
    /// in both directions: an unknown-size parent ends at the first child
    /// that can only be its sibling, and an unknown-size child is handed to
    /// the visitor with its real end already resolved.
    func forEachChild(of parent: Element, _ visit: (Element) -> Bool) {
        var offset = parent.dataOffset
        let terminators = Self.terminators(for: parent.id)
        while offset < parent.endOffset, var child = element(at: offset, limit: parent.endOffset) {
            if parent.isUnknownSize, terminators.contains(child.id) { return }
            if child.isUnknownSize { child = resolvingUnknownSize(child) }
            if !visit(child) { return }
            guard child.endOffset > offset else { return } // no progress: corrupt
            offset = child.endOffset
        }
    }

    /// How deep a chain of unknown-size elements may nest before the file is
    /// treated as malformed. Real files nest Segment inside nothing and
    /// Cluster inside Segment; anything past this is hostile, and each level
    /// costs a crafted file only two bytes.
    static let maxUnknownSizeDepth = 16

    /// Walk an unknown-size element's children to find where it really ends.
    ///
    /// Iterative rather than recursive: nesting is a two-byte-per-level
    /// construct in the file, so recursion here is a stack overflow waiting
    /// to be handed to the app.
    func resolvingUnknownSize(_ element: Element) -> Element {
        // Each entry is an open unknown-size element still looking for its end.
        var open: [(id: UInt32, dataOffset: Int, terminators: Set<UInt32>)] =
            [(element.id, element.dataOffset, Self.terminators(for: element.id))]
        var offset = element.dataOffset
        var resolvedEnd = element.dataOffset

        while !open.isEmpty {
            guard offset < bytes.count, let child = self.element(at: offset) else { break }
            let top = open[open.count - 1]

            if top.terminators.contains(child.id) {
                // This child belongs to an ancestor: everything still open ends here.
                resolvedEnd = offset
                break
            }
            if child.isUnknownSize {
                guard open.count < Self.maxUnknownSizeDepth else { break }
                open.append((child.id, child.dataOffset, Self.terminators(for: child.id)))
                offset = child.dataOffset
                continue
            }
            guard child.endOffset > offset else { break }
            offset = child.endOffset
            resolvedEnd = offset
        }

        return Element(id: element.id, size: nil, dataOffset: element.dataOffset,
                       endOffset: max(resolvedEnd, offset))
    }

    /// IDs that end an unknown-size element of the given type. A Segment runs
    /// to the end of the file; a Cluster (or anything else) ends when a
    /// Segment-level element begins.
    static func terminators(for id: UInt32) -> Set<UInt32> {
        id == MatroskaID.segment ? [] : MatroskaID.segmentLevelIDs
    }
}

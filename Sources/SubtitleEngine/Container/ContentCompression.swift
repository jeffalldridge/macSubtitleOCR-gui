import Compression
import Foundation

/// Matroska lets a track compress its frames, and remuxers routinely do it
/// for subtitles — PGS bitmaps deflate well. A reader that ignores this hands
/// the decoder compressed bytes and finds no subtitles at all.
///
/// https://www.matroska.org/technical/codec_specs.html#contentencodings
public enum ContentCompression: Sendable, Hashable {
    case none
    /// zlib-wrapped DEFLATE (`ContentCompAlgo` 0).
    case zlib
    /// Bytes the muxer stripped from the front of every frame
    /// (`ContentCompAlgo` 3), to be put back.
    case headerStripping(Data)

    public var isIdentity: Bool {
        if case .none = self { return true }
        return false
    }

    /// Restore one frame to what the codec expects.
    ///
    /// Returns nil when the frame cannot be decoded, which the caller treats
    /// as a frame to skip rather than a reason to fail the whole track.
    public func decode(_ frame: Data) -> Data? {
        switch self {
        case .none:
            return frame
        case .headerStripping(let prefix):
            return prefix + frame
        case .zlib:
            return Self.inflate(frame)
        }
    }

    /// Inflate a zlib stream.
    ///
    /// Apple's `COMPRESSION_ZLIB` is raw DEFLATE, so the two-byte zlib header
    /// comes off first; the trailing Adler-32 is simply left unread.
    static func inflate(_ data: Data) -> Data? {
        guard data.count > 2 else { return nil }
        // 0x78 is the usual CMF for deflate with a 32 KB window.
        let hasHeader = data[data.startIndex] & 0x0F == 8
        let body = hasHeader ? data.dropFirst(2) : data[...]
        guard !body.isEmpty else { return nil }

        // Subtitle frames are small; start generous and grow if it fills.
        var capacity = max(body.count * 8, 64 * 1024)
        for _ in 0..<8 {
            var output = Data(count: capacity)
            let produced: Int = output.withUnsafeMutableBytes { destination in
                body.withUnsafeBytes { source in
                    guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                          let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(destinationBase, capacity,
                                                     sourceBase, body.count,
                                                     nil, COMPRESSION_ZLIB)
                }
            }
            if produced == 0 { return nil }
            if produced < capacity {
                output.removeSubrange(produced...)
                return output
            }
            // Filled the buffer exactly: it may have been truncated, so retry
            // with room to spare.
            capacity *= 4
        }
        return nil
    }

    /// Read a track's `ContentEncodings`, if it has any.
    ///
    /// Only encodings that apply to frame data are relevant here; an
    /// encrypted track cannot be read at all and is reported as such.
    static func parse(_ encodings: EBMLReader.Element, reader: EBMLReader) -> (compression: ContentCompression, unreadable: String?) {
        var result: ContentCompression = .none
        var encrypted = false

        reader.forEachChild(of: encodings) { encoding in
            guard encoding.id == MatroskaID.contentEncoding else { return true }
            var scope: UInt64 = 1 // frames, per the spec's default
            var type: UInt64 = 0  // compression
            var algorithm: UInt64 = 0
            var settings = Data()
            var sawCompression = false

            reader.forEachChild(of: encoding) { field in
                switch field.id {
                case MatroskaID.contentEncodingScope:
                    scope = reader.uint(field) ?? 1
                case MatroskaID.contentEncodingType:
                    type = reader.uint(field) ?? 0
                case MatroskaID.contentCompression:
                    sawCompression = true
                    reader.forEachChild(of: field) { setting in
                        switch setting.id {
                        case MatroskaID.contentCompAlgo:
                            algorithm = reader.uint(setting) ?? 0
                        case MatroskaID.contentCompSettings:
                            settings = reader.data(setting) ?? Data()
                        default:
                            break
                        }
                        return true
                    }
                default:
                    break
                }
                return true
            }

            guard scope & 1 != 0 else { return true } // not frame data
            if type == 1 {
                encrypted = true
                return false
            }
            guard sawCompression else { return true }

            switch algorithm {
            case 0: result = .zlib
            case 3: result = .headerStripping(settings)
            default: encrypted = false; result = .none
            }
            return true
        }

        if encrypted { return (.none, "This track is encrypted and cannot be read.") }
        return (result, nil)
    }
}

/// Matroska / EBML element IDs, written with their marker bits as in the
/// specification (https://www.matroska.org/technical/elements.html).
enum MatroskaID {
    // EBML header
    static let ebmlHeader: UInt32 = 0x1A45_DFA3
    static let docType: UInt32 = 0x4282

    // Segment and its top-level children
    static let segment: UInt32 = 0x1853_8067
    static let seekHead: UInt32 = 0x114D_9B74
    static let info: UInt32 = 0x1549_A966
    static let tracks: UInt32 = 0x1654_AE6B
    static let cluster: UInt32 = 0x1F43_B675
    static let cues: UInt32 = 0x1C53_BB6B
    static let chapters: UInt32 = 0x1043_A770
    static let tags: UInt32 = 0x1254_C367
    static let attachments: UInt32 = 0x1941_A469
    static let void: UInt32 = 0xEC
    static let crc32: UInt32 = 0xBF

    // SeekHead
    static let seek: UInt32 = 0x4DBB
    static let seekID: UInt32 = 0x53AB
    static let seekPosition: UInt32 = 0x53AC

    // Info
    static let timestampScale: UInt32 = 0x2AD7_B1
    static let duration: UInt32 = 0x4489
    static let title: UInt32 = 0x7BA9

    // Tracks
    static let trackEntry: UInt32 = 0xAE
    static let trackNumber: UInt32 = 0xD7
    static let trackUID: UInt32 = 0x73C5
    static let trackType: UInt32 = 0x83
    static let flagDefault: UInt32 = 0x88
    static let flagForced: UInt32 = 0x55AA
    static let flagLacing: UInt32 = 0x9C
    static let codecID: UInt32 = 0x86
    static let codecPrivate: UInt32 = 0x63A2
    static let name: UInt32 = 0x536E
    static let language: UInt32 = 0x22B5_9C
    static let languageBCP47: UInt32 = 0x22B5_9D

    // Cluster
    static let timestamp: UInt32 = 0xE7
    static let simpleBlock: UInt32 = 0xA3
    static let blockGroup: UInt32 = 0xA0
    static let block: UInt32 = 0xA1
    static let blockDuration: UInt32 = 0x9B

    /// IDs that can only appear directly under Segment. Seeing one of these
    /// while inside an unknown-size Cluster means the cluster has ended.
    static let segmentLevelIDs: Set<UInt32> = [
        seekHead, info, tracks, cluster, cues, chapters, tags, attachments,
    ]

    enum TrackType {
        static let video: UInt64 = 1
        static let audio: UInt64 = 2
        static let subtitle: UInt64 = 17
    }

    enum Codec {
        static let pgs = "S_HDMV/PGS"
        static let vobsub = "S_VOBSUB"
    }
}

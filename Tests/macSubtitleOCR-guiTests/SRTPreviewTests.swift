import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct SRTPreviewTests {
    private let sample = """
1
00:00:01,000 --> 00:00:03,500
Hello, world.

2
00:00:04,000 --> 00:00:06,250
This is a second cue
that wraps onto two lines.

3
00:00:07,000 --> 00:00:09,000
Third cue.

4
00:01:23,450 --> 00:01:25,000
Fourth cue.

5
01:05:30,000 --> 01:05:32,000
Late cue.

"""

    @Test func parsesFirstCuesUpToMaxAndTotalCount() {
        let preview = SRTPreviewLoader.parse(sample, maxCues: 3)
        #expect(preview.totalCount == 5)
        #expect(preview.cues.count == 3)
        #expect(preview.cues[0].text == "Hello, world.")
        #expect(preview.cues[1].text == "This is a second cue that wraps onto two lines.")
        #expect(preview.cues[2].text == "Third cue.")
    }

    @Test func compactsTimingsForDisplay() {
        let preview = SRTPreviewLoader.parse(sample, maxCues: 5)
        #expect(preview.cues[0].timing == "00:01 → 00:03")    // sub-hour
        #expect(preview.cues[3].timing == "01:23 → 01:25")    // sub-hour
        #expect(preview.cues[4].timing == "1:05:30 → 1:05:32") // hour-or-more
    }

    @Test func handlesCRLFLineEndings() {
        let withCRLF = sample.replacingOccurrences(of: "\n", with: "\r\n")
        let preview = SRTPreviewLoader.parse(withCRLF, maxCues: 2)
        #expect(preview.totalCount == 5)
        #expect(preview.cues.first?.text == "Hello, world.")
    }

    @Test func emptyInputReturnsEmpty() {
        let preview = SRTPreviewLoader.parse("", maxCues: 4)
        #expect(preview.cues.isEmpty)
        #expect(preview.totalCount == 0)
    }
}

import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct SRTFileTests {
    @Test func formatsTimestamps() {
        #expect(SRTFile.timestamp(3723.456) == "01:02:03,456")
        #expect(SRTFile.timestamp(0) == "00:00:00,000")
        #expect(SRTFile.timestamp(1.9995) == "00:00:02,000")
        #expect(SRTFile.timestamp(107.25) == "00:01:47,250")
        #expect(SRTFile.timestamp(-1) == "00:00:00,000")
    }

    @Test func parsesTimestamps() {
        #expect(SRTFile.parseTimestamp("01:02:03,456") == 3723.456)
        #expect(SRTFile.parseTimestamp("01:02:03.456") == 3723.456)
        #expect(SRTFile.parseTimestamp("nonsense") == nil)
    }

    @Test func rendersCues() {
        let cues = [
            SRTCue(index: 1, start: 107.25, end: 109.22, text: "This blade has a dark past."),
            SRTCue(index: 2, start: 111.8, end: 115.8, text: "It has shed\nmuch innocent blood."),
        ]
        let expected = "1\n00:01:47,250 --> 00:01:49,220\nThis blade has a dark past.\n\n"
            + "2\n00:01:51,800 --> 00:01:55,800\nIt has shed\nmuch innocent blood.\n\n"
        #expect(SRTFile.render(cues) == expected)
    }

    @Test func roundTrips() {
        let cues = [
            SRTCue(index: 1, start: 1, end: 2.5, text: "Hello"),
            SRTCue(index: 2, start: 3, end: 4, text: "Two\nlines"),
        ]
        #expect(SRTFile.parse(SRTFile.render(cues)) == cues)
    }

    @Test func parsesCRLFBOMAndMissingIndexLines() {
        let text = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,000\r\nHello\r\n\r\n00:00:03,000 --> 00:00:04,000\r\nNo index\r\nhere\r\n\r\n\r\n"
        let cues = SRTFile.parse(text)
        #expect(cues.count == 2)
        #expect(cues[0] == SRTCue(index: 1, start: 1, end: 2, text: "Hello"))
        #expect(cues[1] == SRTCue(index: 2, start: 3, end: 4, text: "No index\nhere"))
    }

    @Test func parsesTheReferenceFixture() throws {
        let text = try String(contentsOf: Fixtures.sintelSRT, encoding: .utf8)
        let cues = SRTFile.parse(text)
        #expect(cues.count == 26)
        #expect(cues[0].start == 107.25)
        #expect(cues[0].text == "This blade has a dark past.")
        #expect(cues[2].text == "You're a fool for traveling alone,\nso completely unprepared.")
    }

    @Test func emptyAndGarbageParseToNothing() {
        #expect(SRTFile.parse("").isEmpty)
        #expect(SRTFile.parse("just some text\n\nmore text").isEmpty)
    }
}

@Suite struct SRTTimingTests {
    @Test func missingEndUsesNextStartMinusGap() {
        let ends = SRTTiming.resolveEnds(starts: [10, 12], ends: [nil, 20])
        #expect(ends == [11.9, 20])
    }

    @Test func missingEndCapsAtFiveSeconds() {
        let ends = SRTTiming.resolveEnds(starts: [10, 30], ends: [nil, nil])
        #expect(ends == [15, 35])
    }

    @Test func presentEndIsClampedToNextStart() {
        let ends = SRTTiming.resolveEnds(starts: [10, 12], ends: [13, 14])
        #expect(ends == [12, 14])
    }

    @Test func presentLongEndIsKept() {
        let ends = SRTTiming.resolveEnds(starts: [10, 40], ends: [22, 41])
        #expect(ends == [22, 41], "a 12-second cue stays 12 seconds")
    }

    @Test func endBeforeStartIsRepaired() {
        let ends = SRTTiming.resolveEnds(starts: [10, 20], ends: [9, 21])
        #expect(ends[0] > 10)
        #expect(ends[0] <= 20)
    }

    @Test func veryCloseCuesStillGetAPositiveDuration() {
        let ends = SRTTiming.resolveEnds(starts: [10, 10.05], ends: [nil, nil])
        #expect(ends[0] > 10)
    }
}

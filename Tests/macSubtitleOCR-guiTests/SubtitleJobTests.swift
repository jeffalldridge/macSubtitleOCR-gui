import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct SubtitleJobTests {
    @MainActor @Test func startsInIdlePhase() {
        let job = SubtitleJob()
        if case .idle = job.phase { } else { Issue.record("expected .idle"); return }
    }

    @MainActor @Test func transitionsToTracksAfterProbing() {
        let job = SubtitleJob()
        job.input = URL(fileURLWithPath: "/tmp/x.sup")
        job.tracks = [Track(id: 0, codec: .pgs, language: nil, name: nil)]
        job.advanceToTracks()
        if case .tracks = job.phase { } else { Issue.record("expected .tracks") }
    }

    @MainActor @Test func resetClearsState() {
        let job = SubtitleJob()
        job.input = URL(fileURLWithPath: "/tmp/x.sup")
        job.selectedTracks = [Track(id: 0, codec: .pgs, language: nil, name: nil)]
        job.advanceToTracks()
        job.reset()
        #expect(job.input == nil)
        #expect(job.tracks.isEmpty)
        #expect(job.selectedTracks.isEmpty)
        if case .idle = job.phase { } else { Issue.record("expected .idle") }
    }

    @MainActor @Test func defaultSelectionPrefersLanguageAndDefaultTrack() {
        let job = SubtitleJob()
        job.tracks = [
            Track(id: 2, codec: .pgs, language: "spa", name: nil, isDefault: true),
            Track(id: 3, codec: .pgs, language: "eng", name: "English SDH"),
            Track(id: 4, codec: .pgs, language: "eng", name: "English", isDefault: true),
        ]

        job.selectDefaultTrack()

        #expect(job.selectedTrackIDs == [4])
        #expect(job.selectedTracks.map(\.id) == [4])
    }
}

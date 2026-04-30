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

    @MainActor @Test func defaultSelectionTicksAllMatchingLanguages() {
        let job = SubtitleJob()
        job.options.languages = "eng"
        job.tracks = [
            Track(id: 2, codec: .pgs, language: "spa", name: nil, isDefault: true),
            Track(id: 3, codec: .pgs, language: "eng", name: "English SDH"),
            Track(id: 4, codec: .pgs, language: "eng", name: "English", isDefault: true),
        ]

        job.selectDefaultTracks()

        // Both English tracks selected, ordered: default first (id 4), then SDH (id 3).
        #expect(job.selectedTrackIDs == [3, 4])
        // Spanish track (id 2) is NOT selected even though it's marked default,
        // because the user's language preference is English.
        #expect(!job.selectedTrackIDs.contains(2))
    }

    @MainActor @Test func defaultSelectionFallsBackToSingleBestWhenNoLanguageMatches() {
        let job = SubtitleJob()
        job.options.languages = "fra"  // no French tracks
        job.tracks = [
            Track(id: 2, codec: .pgs, language: "eng", name: nil, isDefault: true),
            Track(id: 3, codec: .pgs, language: "spa", name: nil),
        ]

        job.selectDefaultTracks()

        #expect(job.selectedTrackIDs == [2])
    }

    @MainActor @Test func defaultSelectionEmptyForEmptyTrackList() {
        let job = SubtitleJob()
        job.tracks = []
        job.selectDefaultTracks()
        #expect(job.selectedTrackIDs.isEmpty)
    }
}

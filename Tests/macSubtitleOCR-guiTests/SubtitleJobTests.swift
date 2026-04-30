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
}

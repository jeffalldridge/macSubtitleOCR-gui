import Foundation
import Testing
@testable import macSubtitleOCR_gui

@Suite struct ProcessRunnerTests {
    @Test func capturesStdoutAndStatus() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"]
        )

        #expect(result.terminationStatus == 0)
        #expect(String(data: result.stdout, encoding: .utf8) == "hello\n")
        #expect(result.stderr.isEmpty)
    }

    @Test func capturesStderrAndFailureStatus() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo nope >&2; exit 7"]
        )

        #expect(result.terminationStatus == 7)
        #expect(String(data: result.stderr, encoding: .utf8) == "nope\n")
    }
}

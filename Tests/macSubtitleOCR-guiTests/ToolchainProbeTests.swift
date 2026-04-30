import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct ToolchainProbeTests {
    @Test func findsExistingExecutable() throws {
        let lsPath = ToolchainProbe.locate("ls", searchPaths: ["/bin", "/usr/bin"])
        #expect(lsPath?.path == "/bin/ls" || lsPath?.path == "/usr/bin/ls")
    }

    @Test func returnsNilForMissingExecutable() {
        let result = ToolchainProbe.locate("definitely-not-a-real-binary-xyz", searchPaths: ["/bin"])
        #expect(result == nil)
    }

    @Test func searchesPATHWhenProvided() throws {
        let envPATH = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = envPATH.split(separator: ":").map(String.init)
        let result = ToolchainProbe.locate("ls", searchPaths: dirs)
        #expect(result != nil)
    }
}

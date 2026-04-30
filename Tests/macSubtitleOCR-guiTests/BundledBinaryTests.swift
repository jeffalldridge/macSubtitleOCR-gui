// Tests/macSubtitleOCR-guiTests/BundledBinaryTests.swift
import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct BundledBinaryTests {
    @Test func devFallbackPathsIncludeVendorBuild() {
        let paths = BundledBinary.devFallbackPaths()
        #expect(paths.contains { $0.path.hasSuffix("Vendor/macSubtitleOCR/.build/release/macSubtitleOCR") })
    }

    @Test func returnsExecutableIfPresentAtAnyPath() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bundledbinary-test-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let fake = tmp.appendingPathComponent("macSubtitleOCR")
        FileManager.default.createFile(atPath: fake.path, contents: Data("#!/bin/sh\nexit 0\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolved = BundledBinary.firstExisting(in: [fake])
        #expect(resolved == fake)
    }

    @Test func returnsNilWhenNothingPresent() {
        let bogus = URL(fileURLWithPath: "/nonexistent/macSubtitleOCR-\(UUID())")
        #expect(BundledBinary.firstExisting(in: [bogus]) == nil)
    }
}

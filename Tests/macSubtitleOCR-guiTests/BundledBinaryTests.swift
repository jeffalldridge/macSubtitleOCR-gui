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

    // MARK: - Regression: issue #3 (crash on "Run OCR")
    //
    // The shipped .app contains no SwiftPM resource bundle. SwiftPM's generated
    // `Bundle.module` accessor resolves only to `Bundle.main.bundleURL/<name>.bundle`
    // or a *hardcoded absolute path into the build machine's .build directory*, and
    // calls `Swift.fatalError()` when neither exists. Touching it on an end user's
    // machine therefore killed the app with SIGTRAP the instant OCR started.
    //
    // Building the candidate list must never depend on that accessor.

    @Test func buildsCandidatesWithoutAResourceBundle() {
        let paths = BundledBinary.bundledPaths(mainBundle: .main, moduleBundle: nil)
        #expect(!paths.isEmpty, "must still offer candidates when no resource bundle exists")
    }

    @Test func resourceBundleLookupIsOptionalRatherThanFatal() {
        // Must hand back an Optional we can branch on — never trap.
        let bundle: Bundle? = BundledBinary.moduleResourceBundle()
        #expect(bundle == nil || bundle != nil)
    }

    @Test func prefersBinaryInsideTheAppBundle() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("bundledbinary-app-\(UUID())")
        let app = root.appendingPathComponent("Test.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.example.Test</string>
        <key>CFBundleExecutable</key><string>Test</string>
        </dict></plist>
        """.utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))

        let binary = resources.appendingPathComponent("macSubtitleOCR")
        fm.createFile(atPath: binary.path, contents: Data("#!/bin/sh\nexit 0\n".utf8),
                      attributes: [.posixPermissions: 0o755])

        let appBundle = try #require(Bundle(url: app))
        let paths = BundledBinary.bundledPaths(mainBundle: appBundle, moduleBundle: nil)

        #expect(paths.first?.resolvingSymlinksInPath() == binary.resolvingSymlinksInPath(),
                "the binary shipped inside the .app must be the first candidate")
    }
}

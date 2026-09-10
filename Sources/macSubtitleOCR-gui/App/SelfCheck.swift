import Foundation

/// Headless sanity check for an assembled `.app`, run via `--self-check`.
///
/// Packaging bugs do not show up in unit tests (they run inside the build
/// tree), so `Scripts/make-app.sh` and CI run this against the bundle they
/// just built.
enum SelfCheck {
    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "macSubtitleOCR \(version) (\(build))"
    }

    static func run() -> Int32 {
        var failures: [String] = []
        let bundle = Bundle.main
        print("macSubtitleOCR self-check")
        print("  bundle: \(bundle.bundleURL.path)")
        print("  version: \(versionString)")

        let insideApp = bundle.bundleURL.pathExtension == "app"
        if insideApp {
            let info = bundle.infoDictionary ?? [:]
            for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "LSMinimumSystemVersion",
                        "CFBundleDocumentTypes", "CFBundleIconName", "NSServices"] {
                if info[key] == nil { failures.append("Info.plist is missing \(key)") }
            }
            let resources = bundle.resourceURL ?? bundle.bundleURL
            for name in ["Assets.car", "AppIcon.icns"] {
                if !FileManager.default.fileExists(atPath: resources.appendingPathComponent(name).path) {
                    failures.append("Resources/\(name) is missing")
                }
            }
            print("  Info.plist keys and icon assets: \(failures.isEmpty ? "ok" : "problems")")
        } else {
            print("  not inside an .app; skipping bundle checks")
        }

        // The engine must work in this process.
        let sample = PGSSelfTest.run()
        print("  engine: \(sample ?? "ok")")
        if let sample { failures.append(sample) }

        for failure in failures { print("  FAIL: \(failure)") }
        print(failures.isEmpty ? "self-check passed" : "self-check FAILED (\(failures.count))")
        return failures.isEmpty ? 0 : 1
    }
}

import SubtitleEngine

/// Decode a tiny synthetic PGS stream to prove the engine is linked and sane.
enum PGSSelfTest {
    static func run() -> String? {
        // One display set: PCS, PDS, ODS (4×2 solid), END.
        func segment(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] {
            [0x50, 0x47, 0, 0, 0, 0, 0, 0, 0, 0, type] + [UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)] + payload
        }
        var bytes: [UInt8] = []
        bytes += segment(0x16, [0x07, 0x80, 0x04, 0x38, 0x10, 0, 1, 0x80, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0])
        bytes += segment(0x14, [0, 0, 1, 235, 128, 128, 255])
        let rle: [UInt8] = [0x00, 0x84, 0x01, 0x00, 0x00, 0x00, 0x84, 0x01, 0x00, 0x00]
        bytes += segment(0x15, [0, 0, 0, 0xC0, 0, 0, UInt8(rle.count + 4), 0, 4, 0, 2] + rle)
        bytes += segment(0x80, [])
        do {
            let stream = try PGSStream(data: Data(bytes))
            guard stream.cues.count == 1 else { return "engine indexed \(stream.cues.count) cues, expected 1" }
            guard let bitmap = try stream.bitmap(at: 0), bitmap.width == 4, bitmap.height == 2 else {
                return "engine decoded the wrong bitmap"
            }
            guard bitmap.cgImage(style: .recognition(invert: false)) != nil else { return "engine could not render" }
            return nil
        } catch {
            return "engine failed: \(error.localizedDescription)"
        }
    }
}

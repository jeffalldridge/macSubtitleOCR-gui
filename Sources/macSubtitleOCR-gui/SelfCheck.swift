import Foundation

/// Headless health check for an assembled `.app`, run via `--self-check`.
///
/// Exists because issue #3 shipped: the app launched fine and only died when
/// the user clicked "Run OCR", and it never failed on the build machine. Unit
/// tests run inside the SwiftPM build tree, so they cannot see that class of
/// packaging bug. `Scripts/make-app.sh` and CI run this against the bundle they
/// just assembled, so a broken package fails the build instead of the user.
enum SelfCheck {
    static func run() -> Int32 {
        var failures = 0
        print("macSubtitleOCR-gui self-check")
        print("  bundle: \(Bundle.main.bundleURL.path)")

        // 1. The OCR binary must resolve, and must resolve from inside the app.
        do {
            let binary = try BundledBinary.resolve()
            print("  macSubtitleOCR: \(binary.path)")

            let appRoot = Bundle.main.bundleURL.resolvingSymlinksInPath()
            if appRoot.pathExtension == "app" {
                let resolved = binary.resolvingSymlinksInPath().path
                if !resolved.hasPrefix(appRoot.path + "/") {
                    print("  FAIL: resolved outside the app bundle — the shipped .app is not self-contained.")
                    failures += 1
                }
            }
        } catch {
            print("  FAIL: \(error.localizedDescription)")
            failures += 1
        }

        // 2. MKVToolNix is a user-installed runtime dependency, not something we
        //    ship, so report it without failing the build.
        if let toolchain = ToolchainProbe.mkvtoolnix() {
            print("  mkvmerge: \(toolchain.mkvmerge.path)")
        } else {
            print("  mkvmerge: not found (users install MKVToolNix via Homebrew)")
        }

        print(failures == 0 ? "self-check passed" : "self-check FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }
}

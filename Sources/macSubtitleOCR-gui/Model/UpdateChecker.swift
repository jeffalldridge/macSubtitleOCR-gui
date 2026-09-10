import Foundation
import Observation

/// Checks GitHub Releases for a newer version. Never downloads anything.
@Observable
final class UpdateChecker {
    struct Available: Equatable {
        let version: String
        let url: URL
    }

    static let releasesAPI = URL(string: "https://api.github.com/repos/jeffalldridge/macSubtitleOCR-gui/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/jeffalldridge/macSubtitleOCR-gui/releases/latest")!
    static let interval: TimeInterval = 24 * 3600

    var available: Available?
    var lastError: String?
    var isChecking = false

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// `v1.2.0` vs `1.1.9` → true. Compares numeric components; anything
    /// after a dash (pre-release) is ignored.
    static func isNewer(_ tag: String, than version: String) -> Bool {
        func components(_ s: String) -> [Int] {
            var core = s.trimmingCharacters(in: .whitespaces)
            if core.hasPrefix("v") || core.hasPrefix("V") { core.removeFirst() }
            core = String(core.split(separator: "-").first ?? "")
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = components(tag)
        let b = components(version)
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Run a check if the setting allows and a day has passed.
    func checkIfDue(settings: AppSettings) async {
        guard settings.checkForUpdates else { return }
        if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < Self.interval { return }
        await check(settings: settings, userInitiated: false)
    }

    /// Run a check now. Errors are kept in `lastError`.
    func check(settings: AppSettings, userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        lastError = nil
        do {
            var request = URLRequest(url: Self.releasesAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            struct Release: Decodable {
                let tag_name: String
                let html_url: String
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            settings.lastUpdateCheck = Date()
            let newer = Self.isNewer(release.tag_name, than: Self.currentVersion)
            let skipped = !userInitiated && settings.skippedUpdateVersion == release.tag_name
            if newer, !skipped {
                available = Available(version: release.tag_name, url: URL(string: release.html_url) ?? Self.releasesPage)
            } else {
                available = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func skip(settings: AppSettings) {
        settings.skippedUpdateVersion = available?.version
        available = nil
    }
}

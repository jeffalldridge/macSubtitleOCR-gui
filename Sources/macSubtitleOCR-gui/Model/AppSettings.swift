import Foundation
import Observation

/// User preferences, persisted to `UserDefaults` as they change.
@Observable
final class AppSettings {
    enum ConflictPolicy: String, CaseIterable, Codable, Identifiable {
        case addSuffix
        case replace

        var id: String { rawValue }

        var label: String {
            switch self {
            case .addSuffix: "Add a number to the new file"
            case .replace: "Replace the existing file"
            }
        }
    }

    struct Snapshot: Codable, Equatable {
        var outputFolderPath: String?
        /// Whether a run asks for a folder before it starts. Decodes to false
        /// for anyone upgrading, which keeps their current behaviour.
        var asksForOutputFolder = false
        var conflictPolicy = ConflictPolicy.addSuffix
        var defaultLanguages = ["en"]
        var invert = false
        var customWords = ""
        var correctLowercaseL = true
        var notifyWhenDone = true
        var openReviewWhenDone = true
        var checkForUpdates = true
        var lastUpdateCheck: Date?
        var skippedUpdateVersion: String?
    }

    static let storageKey = "com.tentstudios.macSubtitleOCR.settings.v1"

    /// Releases up to 0.2 stored their OCR options under this key. Those
    /// preferences are carried over once, on first launch of 1.0.
    static let legacyOptionsKey = "macSubtitleOCRGUI.OCROptions.v1"

    /// The shape v0.2 stored. Only the fields that still exist are carried over.
    private struct LegacyOptions: Decodable {
        var languages: String
        var invert: Bool
        var customWords: String?
    }

    /// Settings carried over from a pre-1.0 install, or nil when there are none.
    static func migratedFromLegacy(in defaults: UserDefaults = .standard) -> Snapshot? {
        guard let data = defaults.data(forKey: legacyOptionsKey),
              let options = try? JSONDecoder().decode(LegacyOptions.self, from: data) else {
            return nil
        }
        var snapshot = Snapshot()
        // v0.2 stored a comma-separated list of ISO 639 codes.
        let languages = words(from: options.languages)
        if !languages.isEmpty { snapshot.defaultLanguages = languages }
        snapshot.invert = options.invert
        snapshot.customWords = options.customWords ?? ""
        return snapshot
    }

    /// Nil means "next to the source file".
    var outputFolder: URL? { didSet { save() } }
    var asksForOutputFolder = false { didSet { save() } }
    var conflictPolicy: ConflictPolicy { didSet { save() } }
    /// BCP 47 identifiers Vision should try, in order.
    var defaultLanguages: [String] { didSet { save() } }
    var invert: Bool { didSet { save() } }
    /// Raw text; split on commas and newlines when used.
    var customWords: String { didSet { save() } }
    var correctLowercaseL: Bool { didSet { save() } }
    var notifyWhenDone: Bool { didSet { save() } }
    var openReviewWhenDone: Bool { didSet { save() } }
    var checkForUpdates: Bool { didSet { save() } }
    var lastUpdateCheck: Date? { didSet { save() } }
    var skippedUpdateVersion: String? { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var snapshot = Snapshot()
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = stored
        } else if let carriedOver = Self.migratedFromLegacy(in: defaults) {
            snapshot = carriedOver
        }
        outputFolder = snapshot.outputFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        asksForOutputFolder = snapshot.asksForOutputFolder
        conflictPolicy = snapshot.conflictPolicy
        defaultLanguages = snapshot.defaultLanguages
        invert = snapshot.invert
        customWords = snapshot.customWords
        correctLowercaseL = snapshot.correctLowercaseL
        notifyWhenDone = snapshot.notifyWhenDone
        openReviewWhenDone = snapshot.openReviewWhenDone
        checkForUpdates = snapshot.checkForUpdates
        lastUpdateCheck = snapshot.lastUpdateCheck
        skippedUpdateVersion = snapshot.skippedUpdateVersion
        isLoading = false
    }

    /// Custom words as a clean list.
    var customWordList: [String] {
        Self.words(from: customWords)
    }

    static func words(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func resetToDefaults() {
        let fresh = Snapshot()
        outputFolder = nil
        asksForOutputFolder = fresh.asksForOutputFolder
        conflictPolicy = fresh.conflictPolicy
        defaultLanguages = fresh.defaultLanguages
        invert = fresh.invert
        customWords = fresh.customWords
        correctLowercaseL = fresh.correctLowercaseL
        notifyWhenDone = fresh.notifyWhenDone
        openReviewWhenDone = fresh.openReviewWhenDone
        checkForUpdates = fresh.checkForUpdates
    }

    private func save() {
        guard !isLoading else { return }
        let snapshot = Snapshot(outputFolderPath: outputFolder?.path,
                                asksForOutputFolder: asksForOutputFolder,
                                conflictPolicy: conflictPolicy,
                                defaultLanguages: defaultLanguages,
                                invert: invert,
                                customWords: customWords,
                                correctLowercaseL: correctLowercaseL,
                                notifyWhenDone: notifyWhenDone,
                                openReviewWhenDone: openReviewWhenDone,
                                checkForUpdates: checkForUpdates,
                                lastUpdateCheck: lastUpdateCheck,
                                skippedUpdateVersion: skippedUpdateVersion)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

extension AppSettings {
    /// Where runs write, as one value rather than two fields that can
    /// disagree.
    var outputDestination: OutputDestination {
        get {
            if asksForOutputFolder { return .askEachTime }
            if let outputFolder { return .folder(outputFolder) }
            return .nextToSource
        }
        set {
            switch newValue {
            case .nextToSource:
                asksForOutputFolder = false
                outputFolder = nil
            case .folder(let url):
                asksForOutputFolder = false
                outputFolder = url
            case .askEachTime:
                asksForOutputFolder = true
            }
        }
    }
}

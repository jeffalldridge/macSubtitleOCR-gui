import AppKit
import SubtitleEngine
import UniformTypeIdentifiers

/// Open panels and drop handling, shared so every route behaves the same.
enum FileImport {
    static var allowedTypes: [UTType] {
        SubtitleSource.supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    static func isSupported(_ url: URL) -> Bool {
        SubtitleSource.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Show an Open panel and add the chosen files to the queue.
    static func presentOpenPanel(into queue: ConversionQueue) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose video or subtitle files. MKV, MKS, SUP, and SUB/IDX are supported."
        guard panel.runModal() == .OK else { return }
        queue.add(urls: panel.urls)
    }

    /// Ask for an output folder.
    static func presentFolderPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where subtitle files are saved."
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Accept file URLs from a drop, expanding folders one level deep.
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var result: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            guard let url else { continue }
            result.append(contentsOf: expand(url))
        }
        return result
    }

    /// A folder becomes its supported files (sorted); a file stays a file.
    static func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if isDirectory.boolValue {
            let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                         options: [.skipsHiddenFiles])) ?? []
            return contents.filter(isSupported).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        return isSupported(url) ? [url] : []
    }
}

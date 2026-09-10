import SubtitleEngine
import SwiftUI

/// Recognition and output options for the current queue.
struct InspectorView: View {
    @Environment(ConversionQueue.self) private var queue
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var queue = queue

        Form {
            Section("Recognition") {
                LanguageChecklist(selection: $queue.runOptions.languages)

                Toggle("Invert images before recognition", isOn: $queue.runOptions.invert)
                    .help("Try this when captions are dark text on a light box.")

                Toggle("Correct lowercase l to I (English)", isOn: $queue.runOptions.correctLowercaseL)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom words")
                    TextField("Names, places, one per line or comma-separated",
                              text: $queue.runOptions.customWords, axis: .vertical)
                        .lineLimit(2...6)
                    Text("Words the recognizer should prefer, such as character names.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Output") {
                OutputLocationPicker(folder: $queue.runOptions.outputFolder)

                Picker("If a file exists", selection: $queue.runOptions.conflictPolicy) {
                    ForEach(AppSettings.ConflictPolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }

                if let track = queue.selectedTrack, let file = queue.file(for: track) {
                    LabeledContent("File name") {
                        Text(previewName(track: track, file: file))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Button("Reset to Defaults") {
                    queue.runOptions = RunOptions(settings: settings)
                }
                .disabled(queue.runOptions == RunOptions(settings: settings))
            } footer: {
                Text("These options apply to this run. Change the defaults in Settings.")
            }
        }
        .formStyle(.grouped)
        .disabled(queue.isRunning)
        .navigationTitle("Options")
    }

    private func previewName(track: QueueTrack, file: QueueFile) -> String {
        let code = OutputNaming.languageCode(for: track.info, fallback: queue.runOptions.fallbackLanguage)
        return OutputNaming.filename(base: file.url.deletingPathExtension().lastPathComponent,
                                     languageCode: code, trackName: track.info.name)
    }
}

/// Multi-select of Vision's supported languages, shown as a menu with check marks.
struct LanguageChecklist: View {
    @Binding var selection: [String]
    @State private var supported: [Locale.Language] = []

    var body: some View {
        LabeledContent("Languages") {
            Menu {
                ForEach(supported, id: \.minimalIdentifier) { language in
                    Toggle(isOn: binding(for: language)) {
                        Text(Self.name(for: language))
                    }
                }
            } label: {
                Text(summary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            .help("Languages to try, in order. A track’s own language is always added first.")
        }
        .task {
            supported = await TextRecognizer.supportedLanguages()
        }
    }

    private var summary: String {
        let names = selection.map { LanguageCode.displayName($0) }
        if names.isEmpty { return "Automatic" }
        if names.count <= 3 { return names.joined(separator: ", ") }
        return "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2)"
    }

    private func binding(for language: Locale.Language) -> Binding<Bool> {
        let id = language.minimalIdentifier
        return Binding(
            get: { selection.contains(id) },
            set: { on in
                if on {
                    if !selection.contains(id) { selection.append(id) }
                } else {
                    selection.removeAll { $0 == id }
                }
            }
        )
    }

    static func name(for language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.maximalIdentifier)
            ?? LanguageCode.displayName(language.minimalIdentifier)
    }
}

/// "Next to the source file" or a chosen folder.
struct OutputLocationPicker: View {
    @Binding var folder: URL?

    var body: some View {
        Picker("Save to", selection: Binding(
            get: { folder == nil ? Choice.nextToSource : .folder },
            set: { choice in
                switch choice {
                case .nextToSource: folder = nil
                case .folder:
                    if let chosen = FileImport.presentFolderPanel() { folder = chosen }
                }
            }
        )) {
            Text("Next to the source file").tag(Choice.nextToSource)
            Text(folder.map { "Folder: \($0.lastPathComponent)" } ?? "Choose a folder…").tag(Choice.folder)
        }
        if let folder {
            LabeledContent("Folder") {
                HStack {
                    Text(folder.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Change…") {
                        if let chosen = FileImport.presentFolderPanel() { self.folder = chosen }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private enum Choice: Hashable {
        case nextToSource
        case folder
    }
}

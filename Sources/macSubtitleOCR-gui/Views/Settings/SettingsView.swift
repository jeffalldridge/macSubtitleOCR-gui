import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RecognitionSettingsView()
                .tabItem { Label("Recognition", systemImage: "text.viewfinder") }
        }
        .frame(width: 520)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversionQueue.self) private var queue
    @Environment(UpdateChecker.self) private var updates
    @State private var cacheSize: Int64 = 0

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Output") {
                OutputLocationPicker(folder: $settings.outputFolder)
                Picker("If a file exists", selection: $settings.conflictPolicy) {
                    ForEach(AppSettings.ConflictPolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
            }

            Section("When recognition finishes") {
                Toggle("Show a notification if the app is in the background", isOn: $settings.notifyWhenDone)
                Toggle("Open the first track that needs review", isOn: $settings.openReviewWhenDone)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                HStack {
                    Button("Check Now") {
                        Task { await updates.check(settings: settings, userInitiated: true) }
                    }
                    .disabled(updates.isChecking)
                    if updates.isChecking {
                        ProgressView().controlSize(.small)
                    } else if let available = updates.available {
                        Text("Version \(available.version) is available.")
                        Link("Download", destination: available.url)
                    } else if let error = updates.lastError {
                        Text(error).foregroundStyle(.secondary)
                    } else if settings.lastUpdateCheck != nil {
                        Text("You’re up to date.").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Checks the project’s GitHub releases once a day. Nothing is downloaded or installed automatically.")
            }

            Section {
                HStack {
                    Text("Tracks read from MKV files are cached so reopening a file is instant.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatters.fileSize(cacheSize)).monospacedDigit()
                    Button("Clear") {
                        queue.cache.removeAll()
                        CueImageCache.shared.removeAll()
                        cacheSize = 0
                    }
                    .disabled(cacheSize == 0)
                }
            } header: {
                Text("Cache")
            }
        }
        .formStyle(.grouped)
        .task { cacheSize = queue.cache.totalBytes }
    }
}

struct RecognitionSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                LanguageChecklist(selection: $settings.defaultLanguages)
                Toggle("Invert images before recognition", isOn: $settings.invert)
                Toggle("Correct lowercase l to I (English)", isOn: $settings.correctLowercaseL)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom words")
                    TextField("Names, places, one per line or comma-separated", text: $settings.customWords, axis: .vertical)
                        .lineLimit(2...6)
                }
            } header: {
                Text("Defaults for new queues")
            } footer: {
                Text("A track’s own language is always tried first. These defaults seed the Inspector for each new queue; tracks whose language matches are ticked automatically.")
            }

            Section {
                Button("Reset All Settings") { settings.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }
}

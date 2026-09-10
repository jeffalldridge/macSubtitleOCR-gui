import SwiftUI

/// Where the subtitle files land, said out loud in the toolbar.
///
/// This used to live only in the inspector, which meant the answer to "where
/// did my subtitles go?" was behind a panel most people never opened. It sits
/// next to the button that starts the work instead, so the destination is
/// visible at the moment it matters.
struct OutputDestinationMenu: View {
    let settings: AppSettings
    let isRunning: Bool

    var body: some View {
        let destination = settings.outputDestination
        return Menu {
            Picker("Save subtitle files", selection: binding) {
                Text("Next to the film").tag(Choice.nextToSource)
                Text("Ask each time").tag(Choice.askEachTime)
                if case .folder(let url) = destination {
                    Text(url.lastPathComponent).tag(Choice.folder)
                }
            }
            .pickerStyle(.inline)
            Divider()
            // Always offered, whichever mode is selected: choosing a folder
            // also switches to it, so it is one gesture instead of pick-a-mode
            // then hunt-for-the-second-control.
            Button("Choose Folder…") { chooseFolder() }
        } label: {
            Label(destination.menuTitle, systemImage: "folder")
                .padding(.horizontal, OutputDestinationLayout.labelInset)
        }
        .labelStyle(.titleAndIcon)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isRunning)
        .help(destination.detail)
        .accessibilityLabel("Where subtitle files are saved")
        .accessibilityValue(destination.menuTitle)
    }

    private enum Choice: Hashable {
        case nextToSource
        case folder
        case askEachTime
    }

    private var binding: Binding<Choice> {
        Binding(
            get: {
                switch settings.outputDestination {
                case .nextToSource: .nextToSource
                case .folder: .folder
                case .askEachTime: .askEachTime
                }
            },
            set: { choice in
                switch choice {
                case .nextToSource: settings.outputDestination = .nextToSource
                case .askEachTime: settings.outputDestination = .askEachTime
                case .folder:
                    // Only offered when a folder is already chosen, so this
                    // selects it rather than asking again.
                    if let folder = settings.outputFolder {
                        settings.outputDestination = .folder(folder)
                    } else {
                        chooseFolder()
                    }
                }
            }
        )
    }

    private func chooseFolder() {
        guard let chosen = FileImport.presentFolderPanel() else { return }
        settings.outputDestination = .folder(chosen)
    }
}

import SwiftUI

/// Scrollable, selectable, copyable console output. Shared by the run and
/// failure screens so both present logs identically.
struct LogPanel: View {
    let lines: [String]
    var minHeight: CGFloat = 140

    private var text: String { lines.joined(separator: "\n") }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .id(Self.bottomID)
            }
            .onChange(of: lines.count) {
                // Follow the tail as new output arrives.
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
        }
        .frame(minHeight: minHeight)
        // A semantic fill, so this stays legible in both light and dark mode.
        .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(.separator)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(6)
            .help("Copy log to the clipboard")
            .accessibilityLabel("Copy log")
        }
        .accessibilityLabel("Log output")
    }

    private static let bottomID = "log-bottom"
}

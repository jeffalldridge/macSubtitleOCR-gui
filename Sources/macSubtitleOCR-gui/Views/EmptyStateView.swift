import SwiftUI

/// The drop zone shown when nothing has been added yet.
struct EmptyStateView: View {
    @Environment(ConversionQueue.self) private var queue
    let isTargeted: Bool

    var body: some View {
        ContentUnavailableView {
            Label("Drop video or subtitle files", systemImage: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
        } description: {
            Text("MKV, MKS, SUP, and SUB/IDX files. Drop a whole folder to queue a season.")
        } actions: {
            Button("Choose Files…") {
                FileImport.presentOpenPanel(into: queue)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 16))
                .padding(24)
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File drop area")
        .accessibilityHint("Drop video or subtitle files here, or choose them with the button.")
        .navigationTitle("macSubtitleOCR")
    }
}

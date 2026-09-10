import SwiftUI

/// The drop zone shown when the queue is empty.
struct EmptyQueueView: View {
    @Environment(ConversionQueue.self) private var queue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isTargeted: Bool

    var body: some View {
        ContentUnavailableView {
            Label("Drop video or subtitle files",
                  systemImage: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
        } description: {
            // Two sentences at a fixed width, so the line breaks land in the
            // same place whatever the window is doing.
            VStack(spacing: 4) {
                Text("MKV, MKS, SUP, and SUB/IDX files.")
                Text("Drop a whole folder to queue a season.")
            }
            .frame(maxWidth: EmptyQueueLayout.descriptionWidth)
        } actions: {
            Button("Choose Files…") {
                FileImport.presentOpenPanel(into: queue)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(EmptyQueueLayout.inset)
        .background {
            RoundedRectangle(cornerRadius: EmptyQueueLayout.cornerRadius)
                .strokeBorder(style: StrokeStyle(lineWidth: EmptyQueueLayout.dropBorderWidth, dash: [10, 8]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: EmptyQueueLayout.cornerRadius))
                .padding(EmptyQueueLayout.borderInset)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File drop area")
        .accessibilityHint("Drop video or subtitle files here, or choose them with the button.")
        .navigationTitle("macSubtitleOCR")
    }
}

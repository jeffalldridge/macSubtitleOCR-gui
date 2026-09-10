import SwiftUI

struct AcknowledgementsView: View {
    static let windowID = "acknowledgements"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("macSubtitleOCR builds on the work of others. Thank you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(Licenses.all) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.title).font(.headline)
                            Spacer()
                            if let url = URL(string: entry.url) {
                                Link("Website", destination: url).font(.callout)
                            }
                        }
                        Text(entry.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(entry.text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 400)
        .navigationTitle("Acknowledgements")
    }
}

/// License texts shown in the Acknowledgements window. Kept in source so
/// the app has no resource bundle to go missing.
enum Licenses {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let url: String
        let text: String
    }

    static let all: [Entry] = [
        Entry(id: "macSubtitleOCR",
              title: "macSubtitleOCR",
              subtitle: "Ethan Dye · MIT License. The PGS and VobSub decoders and the Vision recognition pipeline in this app are derived from this project.",
              url: "https://github.com/ecdye/macSubtitleOCR",
              text: mit(copyright: "Copyright © 2024-2026 Ethan Dye")),
        Entry(id: "macSubtitleOCR-gui",
              title: "macSubtitleOCR (this app)",
              subtitle: "Jeff Alldridge / Tent Studios, LLC · MIT License.",
              url: "https://github.com/jeffalldridge/macSubtitleOCR-gui",
              text: mit(copyright: "Copyright © 2026 Jeff Alldridge / Tent Studios, LLC")),
        Entry(id: "sf-symbols",
              title: "SF Symbols",
              subtitle: "Apple Inc. The app icon is composed from the “captions.bubble” symbol under Apple’s SF Symbols license, which permits use within apps.",
              url: "https://developer.apple.com/sf-symbols/",
              text: "Symbols are used as permitted by the Xcode and Apple SDKs Agreement. They are not redistributed as standalone artwork."),
        Entry(id: "sintel",
              title: "Sintel test fixtures",
              subtitle: "Blender Foundation · CC BY 3.0. Short subtitle excerpts of the open movie Sintel are used only in the project’s automated tests; they are not part of the app.",
              url: "https://durian.blender.org",
              text: "© copyright Blender Foundation | durian.blender.org. Licensed under the Creative Commons Attribution 3.0 license."),
    ]

    static func mit(copyright: String) -> String {
        """
        MIT License

        \(copyright)

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all \
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
        SOFTWARE.
        """
    }
}

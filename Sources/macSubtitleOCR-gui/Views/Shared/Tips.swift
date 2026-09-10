import SwiftUI
import TipKit

struct DropFilesTip: Tip {
    var title: Text { Text("Add more files any time") }
    var message: Text? { Text("Drop MKV, SUP, or SUB/IDX files — or a whole folder — anywhere in the window.") }
    var image: Image? { Image(systemName: "arrow.down.doc") }
}

struct EditCueTip: Tip {
    var title: Text { Text("Fix cues right here") }
    var message: Text? { Text("Click a cue’s text to correct it. The subtitle file updates as you type. Flagged cues are the ones worth a look.") }
    var image: Image? { Image(systemName: "pencil.line") }
}

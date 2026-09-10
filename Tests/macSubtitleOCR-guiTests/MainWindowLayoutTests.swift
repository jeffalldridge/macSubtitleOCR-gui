import CoreGraphics
import Testing
@testable import macSubtitleOCR_gui

/// The window's limits are derived from what it has to hold. These check the
/// derivation still holds, so a column that grows widens the window instead of
/// being born clipped.
///
/// Everything is compared as `Double`: Swift's implicit `CGFloat` conversion
/// makes the two sides of a `CGFloat` comparison different types inside the
/// expectation macro, and it reports equal numbers as unequal.
@Suite struct MainWindowLayoutTests {
    private func expectEqual(_ lhs: CGFloat, _ rhs: CGFloat,
                             _ comment: Comment? = nil,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Double(lhs) == Double(rhs), comment, sourceLocation: sourceLocation)
    }

    private func expectAtMost(_ lhs: CGFloat, _ rhs: CGFloat,
                              _ comment: Comment? = nil,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Double(lhs) <= Double(rhs), comment, sourceLocation: sourceLocation)
    }

    @Test func theWindowIsWideEnoughForBothTables() {
        expectAtMost(QueueTableLayout.minimumWidth, MainWindowLayout.minimumWidth)
        expectAtMost(CueTableLayout.minimumWidth, MainWindowLayout.minimumWidth)
        expectAtMost(MainWindowLayout.minimumWidth, MainWindowLayout.idealWidth)
    }

    @Test func theQueueTableAddsUpToItsMinimum() {
        let columns = QueueTableLayout.includeWidth
            + QueueTableLayout.nameMinimumWidth
            + QueueTableLayout.kindMinimumWidth
            + QueueTableLayout.languageMinimumWidth
            + QueueTableLayout.cuesMinimumWidth
            + QueueTableLayout.statusMinimumWidth
        expectEqual(QueueTableLayout.minimumWidth, columns + QueueTableLayout.horizontalChrome)
    }

    @Test func theCueTableAddsUpToItsMinimum() {
        let columns = CueTableLayout.flagWidth
            + CueTableLayout.numberMinimumWidth
            + CueTableLayout.imageMinimumWidth
            + CueTableLayout.timeMinimumWidth
            + CueTableLayout.textMinimumWidth
        expectEqual(CueTableLayout.minimumWidth, columns + CueTableLayout.horizontalChrome)
    }

    @Test func everyColumnCanReachItsIdealWidth() {
        expectAtMost(QueueTableLayout.kindMinimumWidth, QueueTableLayout.kindIdealWidth)
        expectAtMost(QueueTableLayout.kindIdealWidth, QueueTableLayout.kindMaximumWidth)
        expectAtMost(QueueTableLayout.languageMinimumWidth, QueueTableLayout.languageIdealWidth)
        expectAtMost(QueueTableLayout.languageIdealWidth, QueueTableLayout.languageMaximumWidth)
        expectAtMost(QueueTableLayout.cuesMinimumWidth, QueueTableLayout.cuesIdealWidth)
        expectAtMost(QueueTableLayout.cuesIdealWidth, QueueTableLayout.cuesMaximumWidth)
        expectAtMost(QueueTableLayout.statusMinimumWidth, QueueTableLayout.statusIdealWidth)
        expectAtMost(QueueTableLayout.statusIdealWidth, QueueTableLayout.statusMaximumWidth)
        expectAtMost(QueueTableLayout.nameMinimumWidth, QueueTableLayout.nameIdealWidth)

        expectAtMost(CueTableLayout.numberMinimumWidth, CueTableLayout.numberIdealWidth)
        expectAtMost(CueTableLayout.numberIdealWidth, CueTableLayout.numberMaximumWidth)
        expectAtMost(CueTableLayout.imageMinimumWidth, CueTableLayout.imageIdealWidth)
        expectAtMost(CueTableLayout.imageIdealWidth, CueTableLayout.imageMaximumWidth)
        expectAtMost(CueTableLayout.timeMinimumWidth, CueTableLayout.timeIdealWidth)
        expectAtMost(CueTableLayout.timeIdealWidth, CueTableLayout.timeMaximumWidth)
    }

    @Test func theWindowIsTallEnoughForBothPanesAndTheStatusBar() {
        let stacked = MainWindowLayout.queueMinimumHeight
            + MainWindowLayout.detailMinimumHeight
            + MainWindowLayout.dividerThickness
            + StatusBarLayout.height
        expectEqual(MainWindowLayout.minimumHeight, stacked)
        expectAtMost(MainWindowLayout.minimumHeight, MainWindowLayout.idealHeight)
        expectAtMost(MainWindowLayout.queueMinimumHeight, MainWindowLayout.queueIdealHeight)
        expectAtMost(MainWindowLayout.detailMinimumHeight, MainWindowLayout.detailIdealHeight)
    }

    @Test func theDetailPaneCanHoldACuePreviewAndSomeCues() {
        // The preview is a fixed height, so what is left over is the header
        // plus the cue table. Fewer than a few rows of cues and the pane is
        // not worth showing.
        let headerHeight = DetailPaneMetrics.verticalPadding * 2 + 44
        let rowsHeight = MainWindowLayout.detailMinimumHeight - CuePreviewLayout.height - headerHeight
        expectAtMost(CueTableLayout.thumbnailHeight * 3, rowsHeight,
                     "room for at least three cues under the preview")
    }

    @Test func theStatusBarFitsOneLineOfSmallControls() {
        // A small button is 16 points tall; the bar has to clear that plus its
        // padding, or the controls are clipped.
        let smallControlHeight: CGFloat = 16
        expectAtMost(smallControlHeight + StatusBarLayout.verticalPadding * 2, StatusBarLayout.height)
    }

    @Test func theInspectorStaysWithinItsBounds() {
        expectAtMost(MainWindowLayout.inspectorMinimumWidth, MainWindowLayout.inspectorIdealWidth)
        expectAtMost(MainWindowLayout.inspectorIdealWidth, MainWindowLayout.inspectorMaximumWidth)
    }
}

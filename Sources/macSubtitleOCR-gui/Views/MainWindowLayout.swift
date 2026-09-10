import SwiftUI

/// Every fixed measurement in the main window, in one place and derived from
/// the content rather than chosen by eye.
///
/// The window holds two tables stacked vertically: the queue on top and,
/// underneath, whatever the selection calls for — usually the cue review. A
/// number that is only ever right for one of them belongs to that table's
/// section below, and the window's own limits are computed from both.
enum MainWindowLayout {
    /// Room for the wider of the two tables, so neither is born clipped.
    static let minimumWidth = max(QueueTableLayout.minimumWidth, CueTableLayout.minimumWidth)

    /// Wide enough for a full cue image beside its text without scrolling.
    static let idealWidth: CGFloat = 1180

    /// The queue is a reference, not the work surface: a handful of rows is
    /// enough, and the user drags the divider when they want more.
    static let queueMinimumHeight: CGFloat = 116
    static let queueIdealHeight: CGFloat = 208

    /// Below the divider: a header, the cue image at a legible size, and
    /// enough of the cue table to scroll.
    static let detailMinimumHeight: CGFloat = 396
    static let detailIdealHeight: CGFloat = 620

    static let minimumHeight = queueMinimumHeight + detailMinimumHeight
        + dividerThickness + StatusBarLayout.height
    static let idealHeight = queueIdealHeight + detailIdealHeight
        + dividerThickness + StatusBarLayout.height

    static let dividerThickness: CGFloat = 1

    /// The inspector holds a form of labelled controls; narrower than this and
    /// the labels wrap.
    static let inspectorMinimumWidth: CGFloat = 260
    static let inspectorIdealWidth: CGFloat = 300
    static let inspectorMaximumWidth: CGFloat = 380
}

/// The queue table's columns. Minimums are what the widest ordinary value
/// needs; maximums stop a column from eating the space the name column wants.
enum QueueTableLayout {
    /// A checkbox, its focus ring, and the padding a table puts around cell
    /// content. Narrower than this and the control is clipped, which leaves it
    /// visible but with almost nothing left to click.
    static let includeWidth: CGFloat = 36
    /// Long film names are the norm, so this column takes what is left over.
    static let nameMinimumWidth: CGFloat = 220
    static let nameIdealWidth: CGFloat = 380
    /// "VobSub · Track 12".
    static let kindMinimumWidth: CGFloat = 104
    static let kindIdealWidth: CGFloat = 124
    static let kindMaximumWidth: CGFloat = 170
    /// "Portuguese (Brazil)".
    static let languageMinimumWidth: CGFloat = 96
    static let languageIdealWidth: CGFloat = 132
    static let languageMaximumWidth: CGFloat = 190
    /// Five digits and a separator, right-aligned.
    static let cuesMinimumWidth: CGFloat = 62
    static let cuesIdealWidth: CGFloat = 76
    static let cuesMaximumWidth: CGFloat = 104
    /// "1,204 of 1,880" beside a progress ring.
    static let statusMinimumWidth: CGFloat = 138
    static let statusIdealWidth: CGFloat = 176
    static let statusMaximumWidth: CGFloat = 240

    /// The table's own chrome: inset style margins plus a scroller.
    static let horizontalChrome: CGFloat = 26

    static let minimumWidth = includeWidth + nameMinimumWidth + kindMinimumWidth
        + languageMinimumWidth + cuesMinimumWidth + statusMinimumWidth + horizontalChrome

    /// Enough to read a name and a language on one line.
    static let rowVerticalPadding: CGFloat = 2
}

/// The cue review table underneath.
enum CueTableLayout {
    static let flagWidth: CGFloat = 22
    static let numberMinimumWidth: CGFloat = 34
    static let numberIdealWidth: CGFloat = 44
    static let numberMaximumWidth: CGFloat = 60
    /// A 16:9 subtitle strip stays readable down to this width.
    static let imageMinimumWidth: CGFloat = 120
    static let imageIdealWidth: CGFloat = 240
    static let imageMaximumWidth: CGFloat = 440
    /// "1:47:03.250 → 1:47:05.220" in a monospaced face.
    static let timeMinimumWidth: CGFloat = 124
    static let timeIdealWidth: CGFloat = 190
    static let timeMaximumWidth: CGFloat = 230
    /// Two lines of dialogue without wrapping mid-word.
    static let textMinimumWidth: CGFloat = 240

    static let thumbnailHeight: CGFloat = 40
    static let horizontalChrome: CGFloat = 26

    static let minimumWidth = flagWidth + numberMinimumWidth + imageMinimumWidth
        + timeMinimumWidth + textMinimumWidth + horizontalChrome
}

/// The selected cue shown at full size above the cue table.
enum CuePreviewLayout {
    /// A 1920×1080 subtitle strip is about a fifth of the frame height; this
    /// shows one at roughly its on-screen size on a laptop display.
    static let height: CGFloat = 190
    static let imageInset: CGFloat = 24
    static let captionSpacing: CGFloat = 8
}

/// The bar along the bottom, which is always present.
enum StatusBarLayout {
    /// One line of small controls plus its separator.
    static let height: CGFloat = 30
    /// Wider than the panes above it. The window's bottom corners are rounded,
    /// so text run to the same margin as the table would appear to drift into
    /// the curve; setting it in keeps the first and last items clear of it.
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 6
    static let itemSpacing: CGFloat = 10
    /// Wide enough to show meaningful movement, narrow enough to leave the
    /// activity text room.
    static let progressWidth: CGFloat = 150
}

/// The cue search field in the detail header.
enum CueSearchLayout {
    /// Long enough for a phrase of dialogue, short enough to leave the track
    /// title its room.
    static let width: CGFloat = 150
}

/// Shared with the detail header so the two panes line up.
enum DetailPaneMetrics {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 12
    static let titleSpacing: CGFloat = 6
    static let stackSpacing: CGFloat = 3
}

/// The empty queue.
enum EmptyQueueLayout {
    /// Line lengths chosen so the two sentences break where they read best.
    static let descriptionWidth: CGFloat = 380
    static let inset: CGFloat = 40
    static let borderInset: CGFloat = 24
    static let cornerRadius: CGFloat = 16
    static let dropBorderWidth: CGFloat = 2
}

import Foundation
import SwiftUI

enum Formatters {
    /// `1:47.250` or `1:05:30.000`.
    static func clock(_ time: TimeInterval, milliseconds: Bool = true) -> String {
        let total = max(0, Int((time * 1000).rounded()))
        let hours = total / 3_600_000
        let minutes = (total / 60_000) % 60
        let seconds = (total / 1000) % 60
        let millis = total % 1000
        var text = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
        if milliseconds { text += String(format: ".%03d", millis) }
        return text
    }

    /// `1:47.250 → 1:49.220`
    static func range(_ start: TimeInterval, _ end: TimeInterval) -> String {
        "\(clock(start)) → \(clock(end))"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds)) s"
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

/// A small capsule label ("Default", "Forced", "PGS").
struct Badge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(text)
    }
}

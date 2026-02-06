import SwiftUI

/// Shared utilities for formatting and displaying "last seen" time for aircraft data freshness
enum LastSeenFormatting {
    /// Computes seconds elapsed since the given date
    static func secondsSince(_ date: Date, now: Date = Date()) -> Int {
        Int(now.timeIntervalSince(date))
    }

    /// Formats elapsed time as a compact string (e.g., "5s", "2m")
    static func compactText(since date: Date, now: Date = Date()) -> String {
        let seconds = secondsSince(date, now: now)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            return "\(minutes)m"
        }
    }

    /// Formats elapsed time with "ago" suffix (e.g., "5s ago", "2m ago")
    static func textWithAgo(since date: Date, now: Date = Date()) -> String {
        "\(compactText(since: date, now: now)) ago"
    }

    /// Returns a color based on data freshness
    /// - Green: 0-9 seconds (fresh)
    /// - Yellow: 10-29 seconds (aging)
    /// - Orange: 30-44 seconds (stale)
    /// - Red: 45+ seconds (very stale)
    static func color(since date: Date, now: Date = Date()) -> Color {
        let seconds = secondsSince(date, now: now)
        switch seconds {
        case 0..<10:
            return .green
        case 10..<30:
            return .yellow
        case 30..<45:
            return .orange
        default:
            return .red
        }
    }
}

/// Convenience extension on Date for cleaner call sites
extension Date {
    /// Seconds elapsed since this date
    func secondsElapsed(now: Date = Date()) -> Int {
        LastSeenFormatting.secondsSince(self, now: now)
    }

    /// Compact text representation of elapsed time (e.g., "5s")
    func elapsedCompactText(now: Date = Date()) -> String {
        LastSeenFormatting.compactText(since: self, now: now)
    }

    /// Text with "ago" suffix (e.g., "5s ago")
    func elapsedTextWithAgo(now: Date = Date()) -> String {
        LastSeenFormatting.textWithAgo(since: self, now: now)
    }

    /// Color based on freshness
    func freshnessColor(now: Date = Date()) -> Color {
        LastSeenFormatting.color(since: self, now: now)
    }
}

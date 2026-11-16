import Foundation

/// Sorts dated tasks into the groups of the "Termine" page.
public enum Agenda {
    public enum Bucket: Int, CaseIterable, Sendable, Identifiable {
        case overdue, today, week, later

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .overdue: "Überfällig"
            case .today: "Heute"
            case .week: "Nächste 7 Tage"
            case .later: "Später"
            }
        }
    }

    /// A calendar with weeks from Monday to Sunday and ISO week numbers, as used in Germany.
    public static var weekCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }

    /// The 14 days of this week and the next, starting on Monday.
    public static func twoWeeks(around today: Date = .now, calendar: Calendar = weekCalendar) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
        return (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// How many of the due dates fall on each day, keyed by the start of the day.
    public static func counts(of dueDates: [Date], calendar: Calendar = weekCalendar) -> [Date: Int] {
        dueDates.reduce(into: [:]) { $0[calendar.startOfDay(for: $1), default: 0] += 1 }
    }

    /// Whole days count: a task due today is never overdue, whatever the hour.
    public static func bucket(for due: Date, today: Date = .now, calendar: Calendar = .current) -> Bucket {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: due)).day ?? 0
        if days < 0 { return .overdue }
        if days == 0 { return .today }
        return days <= 7 ? .week : .later
    }
}

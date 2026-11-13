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

    /// Whole days count: a task due today is never overdue, whatever the hour.
    public static func bucket(for due: Date, today: Date = .now, calendar: Calendar = .current) -> Bucket {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: due)).day ?? 0
        if days < 0 { return .overdue }
        if days == 0 { return .today }
        return days <= 7 ? .week : .later
    }
}

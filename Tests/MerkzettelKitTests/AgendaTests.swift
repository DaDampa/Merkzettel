import Foundation
import Testing
@testable import MerkzettelKit

@Test("Dates fall into the right group", arguments: [
    (-3, Agenda.Bucket.overdue), (-1, .overdue), (0, .today), (1, .week), (7, .week), (8, .later), (40, .later),
])
func buckets(_ offset: Int, expected: Agenda.Bucket) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 23, minute: 30))!
    let due = calendar.date(byAdding: .day, value: offset, to: calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 0, minute: 5))!)!
    #expect(Agenda.bucket(for: due, today: today, calendar: calendar) == expected)
}

@Test func twoWeeksStartOnMondayOfThisWeek() {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    // Thursday, 19 November 2026.
    let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 15))!
    let days = Agenda.twoWeeks(around: today, calendar: calendar)
    #expect(days.count == 14)
    #expect(calendar.dateComponents([.year, .month, .day], from: days[0]) == DateComponents(year: 2026, month: 11, day: 16))
    #expect(calendar.dateComponents([.year, .month, .day], from: days[13]) == DateComponents(year: 2026, month: 11, day: 29))
    #expect(calendar.component(.weekOfYear, from: days[0]) == 47 && calendar.component(.weekOfYear, from: days[7]) == 48)
}

@Test func dueDatesAreCountedPerDay() {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 8))!
    let evening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 22))!
    let next = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 1))!
    let counts = Agenda.counts(of: [morning, evening, next], calendar: calendar)
    #expect(counts[calendar.startOfDay(for: morning)] == 2 && counts[calendar.startOfDay(for: next)] == 1 && counts.count == 2)
}

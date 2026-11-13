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

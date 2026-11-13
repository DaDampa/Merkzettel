import Testing
@testable import MerkzettelKit

@Test("Bullets, numbers, and checkboxes are removed", arguments: [
    ("- Angebot prüfen", "Angebot prüfen"),
    ("  • Termin abstimmen ", "Termin abstimmen"),
    ("1. Lastenheft", "Lastenheft"),
    ("2) Abnahme", "Abnahme"),
    ("- [ ] Rechnung", "Rechnung"),
    ("[x] Kickoff", "Kickoff"),
    ("E-Mail an Kunde - dringend", "E-Mail an Kunde - dringend"),
    ("2026 Planung", "2026 Planung"),
])
func strips(_ input: String, expected: String) {
    #expect(ListParser.strip(input) == expected)
}

@Test func splitsLinesAndSkipsEmpty() {
    #expect(ListParser.items("- A\n\n  \n2. B\r\nC") == ["A", "B", "C"])
    #expect(ListParser.items("  ").isEmpty)
}

@Test func projectNamesAreNeverEmpty() {
    #expect(ListParser.projectName("  Katalog   Import ") == "Katalog Import")
    #expect(ListParser.projectName(" ") == "Neues Projekt")
}

import Testing
@testable import MerkzettelKit

@Test("File names are safe for Obsidian", arguments: [
    ("Katalog-Import", "Katalog-Import"),
    ("Kunde A/B: Phase #2 [neu]", "Kunde A-B- Phase -2 -neu-"),
    ("  .versteckt ", "versteckt"),
    ("", "Projekt"),
])
func obsidianFileNames(_ input: String, expected: String) {
    #expect(ObsidianNote.fileName(input) == expected)
}

@Test func noteListsTasksNotesAndArchive() {
    let text = ObsidianNote.markdown(
        project: "Katalog", folder: "/Users/x/Mein Projekt",
        open: [
            .init(title: "Preisliste importieren", due: "2026-11-13", notes: [
                .init(text: "Import nachts\nProtokoll per Mail"),
                .init(text: "Maske", imageFile: "Merkzettel-1.png"),
                .init(text: "", imageFile: "Merkzettel-2.png"),
            ]),
            .init(title: "Testlauf"),
        ],
        loose: [.init(text: "Allgemeines")],
        archived: [.init(title: "Konzept freigeben", due: "2026-11-01", done: "2026-11-03", notes: [.init(text: "Freigabe PL")])],
        finished: [.init(note: .init(text: "KW 48"), taskTitle: "Termin", done: "2026-11-04")]
    )
    #expect(text.hasPrefix("---\ntags:\n  - merkzettel\n"))
    #expect(text.contains("Projektordner: [/Users/x/Mein Projekt](file:///Users/x/Mein%20Projekt)"))
    #expect(text.contains("## Offene Aufgaben\n\n- [ ] Preisliste importieren 📅 2026-11-13\n\t- Import nachts\n\t  Protokoll per Mail\n\t- Maske\n\t  ![[Merkzettel-1.png]]\n\t- ![[Merkzettel-2.png]]\n- [ ] Testlauf\n"))
    #expect(text.contains("## Notizen ohne Aufgabe\n\n- Allgemeines"))
    #expect(text.contains("## Archiv\n\n- [x] Konzept freigeben 📅 2026-11-01 ✅ 2026-11-03\n\t- Freigabe PL\n- Notiz zu „Termin“, abgeschlossen 2026-11-04\n\t- KW 48"))
}

@Test func archiveCanBeLeftOut() {
    let text = ObsidianNote.markdown(project: "X", open: [], archived: [.init(title: "Alt", done: "2026-01-01")], includeArchive: false)
    #expect(text.contains("Keine offenen Aufgaben.") && !text.contains("## Archiv"))
}

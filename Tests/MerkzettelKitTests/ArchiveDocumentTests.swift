import Testing
@testable import MerkzettelKit

@Test("Folder names are safe", arguments: [
    ("Katalog SQL", "Katalog SQL"),
    ("Kunde A/B: Phase 2", "Kunde A-B- Phase 2"),
    ("  .versteckt ", "versteckt"),
    (" / ", "-"),
    ("", "Projekt"),
])
func folderNames(_ input: String, expected: String) {
    #expect(ArchiveDocument.folderName(input) == expected)
}

@Test func archiveListsTasksWithNotesAndPictures() {
    let text = ArchiveDocument.markdown(project: "Katalog", items: [
        .init(title: "Konzept freigeben", isTask: true, date: "03.11.2026, 10:00", notes: [
            .init(text: "Freigabe durch PL\nzweite Zeile"),
            .init(text: "Maske", imageFile: "Merkzettel-Bilder/a b.png"),
            .init(text: "", imageFile: "Merkzettel-Bilder/c.png"),
        ]),
        .init(title: "KW 48", isTask: false, date: "04.11.2026, 09:00", taskTitle: "Termin"),
    ])
    #expect(text.contains("# Archiv: Katalog"))
    #expect(text.contains("## Konzept freigeben\n\nErledigt am 03.11.2026, 10:00\n\n- Freigabe durch PL\n  zweite Zeile\n- Maske\n  ![Maske](Merkzettel-Bilder/a%20b.png)\n- ![Bild](Merkzettel-Bilder/c.png)"))
    #expect(text.contains("## Notiz zu „Termin“\n\nAbgeschlossen am 04.11.2026, 09:00\n\n- KW 48"))
}

@Test func emptyArchiveSaysSo() {
    #expect(ArchiveDocument.markdown(project: "X", items: []).contains("Das Archiv ist leer."))
}

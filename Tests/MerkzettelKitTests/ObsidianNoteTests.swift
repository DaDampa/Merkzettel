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

@Test func projectNoteListsOpenTasksAndLinksTheArchive() {
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
        archiveNote: ObsidianNote.link("Merkzettel/Archiv/Katalog Archiv", alias: "Katalog Archiv"),
        indexNote: ObsidianNote.link("Merkzettel/Merkzettel-Index", alias: "Merkzettel-Index")
    )
    #expect(text.contains("Übersicht: [[Merkzettel/Merkzettel-Index|Merkzettel-Index]]"))
    #expect(text.hasPrefix("---\ntags:\n  - merkzettel\n  - Katalog\nquelle: Merkzettel\n---\n"))
    #expect(text.contains("Projektordner: [/Users/x/Mein Projekt](file:///Users/x/Mein%20Projekt)"))
    #expect(text.contains("Archiv: [[Merkzettel/Archiv/Katalog Archiv|Katalog Archiv]]"))
    #expect(text.contains("## Offene Aufgaben\n\n- [ ] Preisliste importieren 📅 2026-11-13\n\t- Import nachts\n\t  Protokoll per Mail\n\t- Maske\n\t  ![[Merkzettel-1.png]]\n\t- ![[Merkzettel-2.png]]\n- [ ] Testlauf\n"))
    #expect(text.contains("## Notizen ohne Aufgabe\n\n- Allgemeines"))
    #expect(!text.contains("[x]"))
}

@Test func archiveNoteListsDoneTasksAndFinishedNotes() {
    let text = ObsidianNote.archiveMarkdown(
        project: "Katalog", projectNote: ObsidianNote.link("Merkzettel/Katalog", alias: "Katalog"),
        archived: [.init(title: "Konzept freigeben", due: "2026-11-01", done: "2026-11-03", notes: [.init(text: "Freigabe PL")])],
        finished: [.init(note: .init(text: "KW 48"), taskTitle: "Termin", done: "2026-11-04")]
    )
    #expect(text.hasPrefix("---\ntags:\n  - merkzettel-archiv\n  - Katalog\nquelle: Merkzettel\n---\n"))
    #expect(text.contains("Projekt: [[Merkzettel/Katalog|Katalog]]"))
    #expect(text.contains("## Erledigte Aufgaben\n\n- [x] Konzept freigeben 📅 2026-11-01 ✅ 2026-11-03\n\t- Freigabe PL\n"))
    #expect(text.contains("## Abgeschlossene Notizen\n\n- Notiz zu „Termin“, abgeschlossen 2026-11-04\n\t- KW 48"))
}

@Test("Project names become valid tags", arguments: [
    ("Katalog", "Katalog"),
    ("Kunde Nord", "Kunde-Nord"),
    ("Kunde A/B: Phase #2", "Kunde-A-B-Phase-2"),
    ("Größe_XL", "Größe_XL"),
    ("2026", "projekt-2026"),
    (" - ", "projekt"),
])
func projectTags(_ input: String, expected: String) {
    #expect(ObsidianNote.tag(input) == expected)
}

@Test func hashtagsAreFoundOnceInOrder() {
    #expect(ObsidianNote.hashtags(in: ["Angebot #TEST prüfen #kunde/alt", "#test nochmal, #Größe_XL.", "Nr.#5 und #12 und a#b", "#dringend-"])
        == ["TEST", "kunde/alt", "Größe_XL", "dringend"])
    #expect(ObsidianNote.hashtags(in: ["ohne"]).isEmpty)
}

@Test func typedHashtagsBecomeTagsOfTheNote() {
    let text = ObsidianNote.markdown(project: "Katalog", open: [
        .init(title: "Angebot #TEST prüfen", notes: [.init(text: "siehe #Vertrag und #katalog")]),
    ], loose: [.init(text: "#merkzettel")])
    #expect(text.hasPrefix("---\ntags:\n  - merkzettel\n  - Katalog\n  - TEST\n  - Vertrag\nquelle: Merkzettel\n---\n"))
    #expect(text.contains("- [ ] Angebot #TEST prüfen"))
    let archive = ObsidianNote.archiveMarkdown(project: "Katalog", projectNote: "[[Katalog]]",
                                               archived: [.init(title: "Alt #ERLEDIGT", done: "2026-11-01")])
    #expect(archive.hasPrefix("---\ntags:\n  - merkzettel-archiv\n  - Katalog\n  - ERLEDIGT\nquelle: Merkzettel\n---\n"))
}

@Test func emptyNotesSaySo() {
    #expect(ObsidianNote.markdown(project: "X", open: []).contains("Keine offenen Aufgaben."))
    #expect(ObsidianNote.archiveMarkdown(project: "X", projectNote: "[[X]]", archived: []).contains("Keine erledigten Aufgaben."))
    #expect(ObsidianNote.indexMarkdown(parentLink: nil, projects: []).contains("Keine Projekte."))
}

@Test func indexLinksEveryProjectAndTheNoteAbove() {
    let text = ObsidianNote.indexMarkdown(
        parentLink: ObsidianNote.link("10 Projekte/Kunde/Kunde", alias: "Kunde"),
        projects: [
            .init(link: ObsidianNote.link("Merkzettel/Katalog", alias: "Katalog"), openTasks: 3),
            .init(link: ObsidianNote.link("Lager", alias: "Lager"), openTasks: 1),
        ]
    )
    #expect(text.hasPrefix("---\ntags:\n  - merkzettel\nquelle: Merkzettel\n---\n"))
    #expect(text.contains("Übergeordnet: [[10 Projekte/Kunde/Kunde|Kunde]]"))
    #expect(text.contains("## Projekte\n\n- [[Merkzettel/Katalog|Katalog]] – 3 offene Aufgaben\n- [[Lager]] – 1 offene Aufgabe\n"))
}

@Test("Folder paths in the vault are safe", arguments: [
    ("Merkzettel/Archiv", "Merkzettel/Archiv"),
    ("/Projekte//Alt: 2025/", "Projekte/Alt- 2025"),
    ("  ", "Standard"),
])
func folderPaths(_ input: String, expected: String) {
    #expect(ObsidianNote.folderPath(input.trimmingCharacters(in: .whitespaces), fallback: "Standard") == expected)
}

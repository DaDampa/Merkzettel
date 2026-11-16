import AppKit
import SwiftData

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Merkzettel-self.store ~/Applications/Merkzettel.app/Contents/MacOS/Merkzettel --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let context = model.container.mainContext
            func stored<T: PersistentModel>(_ type: T.Type) -> Int { (try? context.fetchCount(FetchDescriptor<T>())) ?? 0 }

            let project = model.addProject(name: "  Test   Projekt ")
            check("a new project is added, named, and selected", project.name == "Test Projekt" && model.projectID == project.id)
            model.addFolders([URL(fileURLWithPath: "/tmp/Ordner A"), URL(fileURLWithPath: "/tmp/Ordner A")])
            check("a folder becomes one project named like the folder",
                  model.projects.filter { $0.folderPath == "/tmp/Ordner A" }.count == 1 && model.project?.name == "Ordner A")

            check("a list becomes one task per line", model.add("- Eins\n2. Zwei\n\n[ ] Drei", kind: .todo, to: project) == 3)
            check("tasks keep their order", project.entries(.todo).map(\.text) == ["Eins", "Zwei", "Drei"])
            check("empty text adds nothing", model.add("   ", kind: .todo, to: project) == 0)

            if let first = project.entries(.todo).first {
                check("a note goes below its task as one entry",
                      model.add("Zeile A\nZeile B", kind: .note, to: project, under: first) == 1 && first.openNotes.map(\.text) == ["Zeile A\nZeile B"])
                model.add("Zweite Notiz", kind: .note, to: project, under: first)
                model.archive(first)
                check("a done task moves to the archive with its notes",
                      project.entries(.todo).count == 2 && project.archive.map(\.text) == ["Eins"] && first.allNotes.count == 2)
                model.restore(first)
                check("a restored task returns to the end of the list, notes intact",
                      project.entries(.todo).map(\.text) == ["Zwei", "Drei", "Eins"] && first.openNotes.count == 2)
                model.move(.todo, in: project, from: IndexSet(integer: 2), to: 0)
                check("moving a task changes the priority order", project.entries(.todo).map(\.text) == ["Eins", "Zwei", "Drei"])
                if let last = project.entries(.todo).last {
                    model.dropText(first.uuid.uuidString, onTaskWithID: last.id)
                    check("a task dragged down takes the place of the task it is dropped on",
                          project.entries(.todo).map(\.text) == ["Zwei", "Drei", "Eins"])
                    if let top = project.entries(.todo).first { model.dropText(first.uuid.uuidString, onTaskWithID: top.id) }
                    check("a task dragged up takes the place of the task it is dropped on",
                          project.entries(.todo).map(\.text) == ["Eins", "Zwei", "Drei"])
                    model.dropText(first.uuid.uuidString, onTaskWithID: first.id)
                    check("a task dropped on itself changes nothing", project.entries(.todo).count == 3 && first.openNotes.count == 2)
                    model.dropText("Hereingezogener Text", onTaskWithID: last.id)
                    check("other text dropped on a task becomes a note", last.openNotes.map(\.text) == ["Hereingezogener Text"])
                    if let note = last.openNotes.first { model.delete(note) }
                }
                if let note = first.openNotes.last {
                    model.archive(note)
                    check("a finished note moves to the archive alone",
                          first.openNotes.count == 1 && project.archive.map(\.text) == ["Zweite Notiz"])
                    model.clearArchive(of: project)
                    check("clearing the archive deletes only archived entries", project.archive.isEmpty && project.entries.count == 4)
                }
                if let note = first.openNotes.first {
                    model.makeTask(note)
                    check("a note can become a task", project.entries(.todo).count == 4 && first.notes.isEmpty)
                    model.delete(note)
                }
                model.add("Hängt an Eins", kind: .note, to: project, under: first)
                let picture = model.addImage(ImageTools.sample(width: 300, height: 200), to: project, under: first)
                check("a picture becomes a note below its task", picture?.hasImage == true && first.openNotes.count == 2)
                if let picture { model.finishEditing(picture) }
                check("a picture without a caption stays", first.openNotes.count == 2)
                check("data that is no picture adds nothing", model.addImage(Data("x".utf8), to: project, under: first) == nil)
                let before = stored(Entry.self)
                model.delete(first)
                check("deleting a task deletes its notes and pictures", stored(Entry.self) == before - 3)
            }
            let entriesBefore = stored(Entry.self)
            model.delete(project)
            check("deleting a project deletes its entries", stored(Entry.self) == entriesBefore - 2 && model.projectID != nil)

            let dated = model.addProject(name: "Termine A")
            let other = model.addProject(name: "Termine B")
            model.add("Später\nOhne Datum", kind: .todo, to: dated)
            model.add("Früher", kind: .todo, to: other)
            if let later = dated.entries(.todo).first, let sooner = other.entries(.todo).first {
                model.setDue(later, Date.now.addingTimeInterval(5 * 86_400))
                model.setDue(sooner, Date.now.addingTimeInterval(-86_400))
                check("Termine lists dated tasks of all projects, soonest first", model.agenda.map(\.text) == ["Früher", "Später"])
                model.archive(sooner)
                check("a done task leaves Termine", model.agenda.map(\.text) == ["Später"])
                model.showsAgenda = true
                model.showInProject(later)
                check("a task in Termine leads to its project and is marked there",
                      !model.showsAgenda && model.projectID == dated.id && model.highlightUUID == later.uuid)
                model.setDue(later, nil)
                check("removing the date removes the task from Termine", model.agenda.isEmpty)
            }
            model.delete(dated)
            model.delete(other)

            let root = URL.temporaryDirectory.appending(path: "Merkzettel-selftest-root", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: root)
            model.rootOverride = root.path
            let filed = model.addProject(name: "Kunde A/B: Phase 2")
            let folder = root.appending(path: "Kunde A-B- Phase 2")
            check("a new project gets a folder in the root folder",
                  filed.folderPath == folder.path && FileManager.default.fileExists(atPath: folder.path), filed.folderPath)
            let twin = model.addProject(name: "Kunde A/B: Phase 2")
            check("a second project of that name gets its own folder", twin.folderPath == folder.path + " 2", twin.folderPath)
            let archiveFile = folder.appending(path: "Merkzettel-Archiv.md")
            check("no archive file before anything is archived", !FileManager.default.fileExists(atPath: archiveFile.path))
            model.add("Abnahme", kind: .todo, to: filed)
            if let task = filed.entries(.todo).first {
                model.add("Protokoll liegt bei", kind: .note, to: filed, under: task)
                model.addImage(ImageTools.sample(width: 200, height: 120), to: filed, under: task)
                model.archive(task)
                let text = (try? String(contentsOf: archiveFile, encoding: .utf8)) ?? ""
                let pictures = (try? FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Merkzettel-Bilder").path)) ?? []
                check("a done task is written to the archive file with notes and pictures",
                      text.contains("## Abnahme") && text.contains("- Protokoll liegt bei") && text.contains("](Merkzettel-Bilder/") && pictures.count == 1, text)
                model.restore(task)
                let after = (try? String(contentsOf: archiveFile, encoding: .utf8)) ?? ""
                let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Merkzettel-Bilder").path)) ?? []
                check("restoring removes it from the archive file", after.contains("Das Archiv ist leer.") && left.isEmpty, after)
            }
            model.delete(filed)
            check("deleting a project keeps its folder", FileManager.default.fileExists(atPath: folder.path))
            model.rootOverride = nil
            try? FileManager.default.removeItem(at: root)

            let vault = URL.temporaryDirectory.appending(path: "Merkzettel-selftest-vault", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: vault)
            try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            let linked = model.addProject(name: "Obsidian: Test")
            model.add("Erste Aufgabe\nZweite Aufgabe", kind: .todo, to: linked)
            if let task = linked.entries(.todo).first {
                model.setDue(task, Date(timeIntervalSince1970: 1_795_000_000))
                model.add("Eine Notiz", kind: .note, to: linked, under: task)
                model.addImage(ImageTools.sample(width: 160, height: 96), to: linked, under: task)
            }
            // A real vault has a ".obsidian" folder at its root; the notes go into a subfolder of it.
            try? FileManager.default.createDirectory(at: vault.appending(path: ".obsidian"), withIntermediateDirectories: true)
            let above = vault.appending(path: "Kunden/Kunde.md")
            try? FileManager.default.createDirectory(at: above.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "# Kunde".write(to: above, atomically: true, encoding: .utf8)
            model.obsidianParentOverride = above.path
            model.obsidianOverride = vault.path
            check("no Obsidian link without a vault in Settings", model.obsidianVault == vault.path)
            model.writeObsidian()
            let noteFile = vault.appending(path: "Merkzettel/Obsidian- Test.md")
            let noteText = (try? String(contentsOf: noteFile, encoding: .utf8)) ?? ""
            let attached = (try? FileManager.default.contentsOfDirectory(atPath: vault.appending(path: "Merkzettel/Anhänge").path)) ?? []
            check("a project becomes a note in the vault with tasks, due date, notes, and pictures",
                  noteText.contains("- [ ] Erste Aufgabe 📅 ") && noteText.contains("\t- Eine Notiz") && noteText.contains("![[Merkzettel-")
                    && noteText.contains("- [ ] Zweite Aufgabe") && attached.count == 1, noteText)
            let indexText = (try? String(contentsOf: vault.appending(path: "Merkzettel/Merkzettel-Index.md"), encoding: .utf8)) ?? ""
            check("the index links every project by path and the note above it",
                  indexText.contains("Übergeordnet: [[Kunden/Kunde|Kunde]]")
                    && indexText.contains("- [[Merkzettel/Obsidian- Test|Obsidian- Test]] – 2 offene Aufgaben"), indexText)
            check("a project note links the index", noteText.contains("Übersicht: [[Merkzettel/Merkzettel-Index|Merkzettel-Index]]"))
            if let task = linked.entries(.todo).first {
                model.archive(task)
                model.writeObsidian()
                let after = (try? String(contentsOf: noteFile, encoding: .utf8)) ?? ""
                let archiveNote = vault.appending(path: "Merkzettel/Archiv/Obsidian- Test Archiv.md")
                let archived = (try? String(contentsOf: archiveNote, encoding: .utf8)) ?? ""
                check("a done task leaves the project note, which links its archive",
                      !after.contains("Erste Aufgabe") && after.contains("Archiv: [[Merkzettel/Archiv/Obsidian- Test Archiv|Obsidian- Test Archiv]]"), after)
                check("the done task stands in the archive note in the archive folder, with notes and picture",
                      archived.contains("- [x] Erste Aufgabe") && archived.contains("\t- Eine Notiz") && archived.contains("![[Merkzettel-")
                        && archived.contains("Projekt: [[Merkzettel/Obsidian- Test|Obsidian- Test]]"), archived)
                model.restore(task)
                model.writeObsidian()
                let restored = (try? String(contentsOf: archiveNote, encoding: .utf8)) ?? ""
                check("a restored task leaves the archive note", restored.contains("Keine erledigten Aufgaben."), restored)
                task.text = "Erste Aufgabe, geändert"
                model.writeObsidian()
                check("changed text reaches the project note",
                      ((try? String(contentsOf: noteFile, encoding: .utf8)) ?? "").contains("- [ ] Erste Aufgabe, geändert"))
            }
            linked.name = "Umbenannt"
            model.writeObsidian()
            check("a renamed project takes its note and its archive note along",
                  !FileManager.default.fileExists(atPath: noteFile.path)
                    && FileManager.default.fileExists(atPath: vault.appending(path: "Merkzettel/Umbenannt.md").path)
                    && FileManager.default.fileExists(atPath: vault.appending(path: "Merkzettel/Archiv/Umbenannt Archiv.md").path))
            model.obsidianOverride = nil
            model.obsidianParentOverride = nil
            model.delete(linked)
            try? FileManager.default.removeItem(at: vault)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}

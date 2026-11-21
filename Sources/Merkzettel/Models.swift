import AppKit
import Foundation
import MerkzettelKit
import SwiftData
import UniformTypeIdentifiers

@Model
final class Project {
    var name: String
    /// A Finder folder this project belongs to. Empty for a project made in the app.
    var folderPath: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()
    /// Where the project's note was written in the Obsidian vault last time, to follow a rename.
    var obsidianNote: String = ""
    /// The same for the project's archive note.
    var obsidianArchive: String = ""
    @Relationship(deleteRule: .cascade, inverse: \Entry.project) var entries: [Entry] = []

    init(name: String) {
        self.name = name
    }

    var hasFolder: Bool { !folderPath.isEmpty }

    /// Open or archived entries of one kind, in list order.
    func entries(_ kind: EntryKind, archived: Bool = false) -> [Entry] {
        entries.filter { $0.kind == kind && $0.isArchived == archived }
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    /// Open notes that belong to no task.
    var looseNotes: [Entry] { entries(.note).filter { $0.parent == nil } }

    /// The archive, newest first: done tasks (their notes come along), and
    /// notes that were finished on their own.
    var archive: [Entry] {
        entries.filter { $0.isArchived && ($0.kind == .todo || $0.parent?.isArchived != true) }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }
}

enum EntryKind: String, CaseIterable, Identifiable {
    case todo, note

    var id: String { rawValue }

    var plural: String {
        switch self {
        case .todo: "Aufgaben"
        case .note: "Notizen"
        }
    }

    var placeholder: String {
        switch self {
        case .todo: "Neue Aufgabe"
        case .note: "Neue Notiz"
        }
    }
}

/// A task, or a note. A task is a heading; its notes hang below it.
@Model
final class Entry {
    var text: String
    var kindRaw: String = "todo"
    var isArchived: Bool = false
    var archivedAt: Date?
    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    var uuid: UUID = UUID()
    var project: Project?
    /// The day a task is due. Notes have none.
    var dueDate: Date?
    /// A picture in a note, as PNG. The text is its caption then.
    @Attribute(.externalStorage) var imageData: Data?
    /// A smaller copy for the list.
    var thumbnail: Data?
    /// The task a note belongs to.
    var parent: Entry?
    @Relationship(deleteRule: .cascade, inverse: \Entry.parent) var notes: [Entry] = []

    init(text: String, kind: EntryKind) {
        self.text = text
        self.kindRaw = kind.rawValue
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .todo }
        set { kindRaw = newValue.rawValue }
    }

    var hasImage: Bool { thumbnail != nil || imageData != nil }

    /// Open tasks that have a due date: what "Termine" shows.
    static var openDatedTasks: Predicate<Entry> {
        #Predicate<Entry> { !$0.isArchived && $0.dueDate != nil && $0.kindRaw == "todo" }
    }

    /// The task's notes that are not finished, in the order they were written.
    var openNotes: [Entry] {
        notes.filter { !$0.isArchived }.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    /// Every note of the task, for the archive.
    var allNotes: [Entry] {
        notes.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }
}

/// What the project page shows. Snapshot mode walks through every case.
enum Page: String, CaseIterable, Identifiable {
    case open, archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Offen"
        case .archive: "Archiv"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    var page: Page = .open
    /// The detail shows "Termine", the dated tasks of all projects, in place of a project.
    var showsAgenda = false
    var projectID: PersistentIdentifier? {
        didSet { persist(project?.uuid.uuidString ?? "", "project.selected") }
    }
    /// The project whose name is being edited in the sidebar.
    var renamingID: PersistentIdentifier?
    /// Set by the menu to move the cursor into the "Neue Aufgabe" field.
    var focusNewTask = false
    /// Counts Shift-Return presses. The text field that has the cursor reacts to a change.
    var shiftReturn = 0
    /// The task whose "Notiz hinzufügen" field should take the cursor.
    var focusNoteFor: UUID?
    /// The text field that has the cursor, by its id. Shift-Return only counts while one has it.
    @ObservationIgnored var focusedField: String?
    /// The note that had the cursor last: what Command-Return opens large,
    /// and what the large note window follows.
    var activeNote: UUID?
    /// What is typed but not yet added in the "Notiz hinzufügen" lines, by field id.
    @ObservationIgnored var addDrafts: [String: String] = [:]
    /// Counts drafts taken over into a note; the field named by `takenDraft` empties itself.
    var draftTaken = 0
    @ObservationIgnored var takenDraft: String?
    /// The text field that should take the cursor, by its id. Set by the arrow keys.
    var focusRequest: String?
    /// The large note window that follows the cursor: the one opened or used last.
    @ObservationIgnored var noteFollower: UUID?
    @ObservationIgnored private var keyMonitor: Any?
    /// The note whose large window has the keyboard. Nil while no note window is in front.
    @ObservationIgnored var frontNote: UUID?
    /// Option-Command-Arrow in a note window: which way to step, and a counter the window reacts to.
    @ObservationIgnored var noteStepOffset = 0
    var noteStepTick = 0
    var projectToDelete: Project?
    /// The task whose circle was clicked. An alert asks before it goes to the archive.
    var taskToComplete: Entry?
    /// The task to scroll to and mark for a moment, after a jump from "Termine".
    var highlightUUID: UUID?
    /// Shown as an alert when a project folder or the archive file cannot be written.
    var folderProblem: String?
    /// Replaces the root folder from Settings in the self-test.
    @ObservationIgnored var rootOverride: String?
    /// Replaces the Obsidian vault from Settings in the self-test.
    @ObservationIgnored var obsidianOverride: String?
    /// Replaces the note above the index from Settings in the self-test.
    @ObservationIgnored var obsidianParentOverride: String?
    @ObservationIgnored private var obsidianTask: Task<Void, Never>?
    /// What Settings shows about the Obsidian notes: when they were written, or why not.
    var obsidianStatus = ""
    var obsidianFailed = false
    var confirmClearArchive = false
    /// The window floats above other apps' windows.
    var alwaysOnTop: Bool = UserDefaults.standard.bool(forKey: "alwaysOnTop") {
        didSet { persist(alwaysOnTop, "alwaysOnTop") }
    }
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { persist(settingsTab.rawValue, "settings.tab") }
    }

    init(container: ModelContainer) {
        self.container = container
        let saved = Store.isOverridden ? "" : UserDefaults.standard.string(forKey: "project.selected") ?? ""
        projectID = (projects.first { $0.uuid.uuidString == saved } ?? projects.first)?.id
        installKeyMonitor()
        // Brings the vault up to date with what changed while the link was off or the app was closed.
        scheduleObsidian()
    }

    private var context: ModelContext { container.mainContext }

    private func persist(_ value: Any, _ key: String) {
        if !Store.isOverridden { UserDefaults.standard.set(value, forKey: key) }
    }

    private func save() {
        try? context.save()
        scheduleObsidian()
    }

    // MARK: Obsidian

    /// The vaults Obsidian knows on this Mac, the open one first.
    static var knownVaults: [String] {
        let file = URL.applicationSupportDirectory.appending(path: "obsidian/obsidian.json")
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = root["vaults"] as? [String: [String: Any]] else { return [] }
        return vaults.values
            .sorted { ($0["open"] as? Bool ?? false ? 0 : 1, $0["path"] as? String ?? "") < ($1["open"] as? Bool ?? false ? 0 : 1, $1["path"] as? String ?? "") }
            .compactMap { $0["path"] as? String }
    }

    /// The vault folder to write into. Empty when the link is off or no vault is chosen.
    var obsidianVault: String {
        if let obsidianOverride { return obsidianOverride }
        guard !Store.isOverridden, UserDefaults.standard.bool(forKey: "obsidian.enabled") else { return "" }
        return UserDefaults.standard.string(forKey: "obsidian.vault") ?? ""
    }

    /// The folder for the project notes inside the vault.
    private var obsidianFolder: String {
        let name = (obsidianOverride == nil ? UserDefaults.standard.string(forKey: "obsidian.folder") : nil) ?? ""
        return ObsidianNote.folderPath(name, fallback: "Merkzettel")
    }

    /// The folder for the archive notes inside the vault, apart from the project notes.
    private var obsidianArchiveFolder: String {
        let name = (obsidianOverride == nil ? UserDefaults.standard.string(forKey: "obsidian.archiveFolder") : nil) ?? ""
        return ObsidianNote.folderPath(name, fallback: "Merkzettel/Archiv")
    }

    /// The note the index hangs below, as a file path. Empty when none is chosen.
    private var obsidianParent: String {
        obsidianOverride != nil ? (obsidianParentOverride ?? "") : (UserDefaults.standard.string(forKey: "obsidian.parent") ?? "")
    }

    /// The real vault: the nearest folder at or above the chosen one that holds
    /// Obsidian's ".obsidian" folder. Links by path count from there.
    static func vaultRoot(of folder: URL) -> URL {
        var candidate = folder.standardizedFileURL
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appending(path: ".obsidian").path) { return candidate }
            candidate = candidate.deletingLastPathComponent()
        }
        return folder.standardizedFileURL
    }

    /// Writes the notes a moment after the last change, so typing does not write on every step.
    private func scheduleObsidian() {
        guard !obsidianVault.isEmpty, obsidianOverride == nil else { return }
        obsidianTask?.cancel()
        obsidianTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { self?.writeObsidian() }
        }
    }

    /// Called on every keystroke in a task or note: the text is saved and goes
    /// to Obsidian once the typing pauses, without waiting for the field to lose focus.
    func textChanged() {
        guard !obsidianVault.isEmpty else { return }
        scheduleObsidian()
    }

    /// The note file of a project in the vault, or nil while the link is off.
    func obsidianFile(for project: Project) -> URL? {
        guard !obsidianVault.isEmpty else { return nil }
        return URL(fileURLWithPath: obsidianVault, isDirectory: true)
            .appending(path: obsidianFolder, directoryHint: .isDirectory)
            .appending(path: ObsidianNote.fileName(project.name) + ".md")
    }

    /// Writes one note per project into the vault. Files change only when their content does.
    func writeObsidian() {
        guard !obsidianVault.isEmpty else { return }
        let manager = FileManager.default
        let vault = URL(fileURLWithPath: obsidianVault, isDirectory: true)
        guard manager.fileExists(atPath: vault.path) else {
            obsidianFailed = true
            obsidianStatus = "Der Vault-Ordner „\(vault.path)“ ist nicht erreichbar."
            return
        }
        let folder = vault.appending(path: obsidianFolder, directoryHint: .isDirectory)
        let pictures = folder.appending(path: "Anhänge", directoryHint: .isDirectory)
        let includeArchive = obsidianOverride != nil || UserDefaults.standard.object(forKey: "obsidian.archive") as? Bool ?? true
        let archiveFolder = vault.appending(path: obsidianArchiveFolder, directoryHint: .isDirectory)
        let root = Self.vaultRoot(of: vault).path
        /// A link by path from the vault root, so it stays exact when note names repeat.
        func link(_ file: URL, alias: String) -> String {
            let path = file.deletingPathExtension().standardizedFileURL.path
            guard path.hasPrefix(root + "/") else { return ObsidianNote.link(alias, alias: alias) }
            return ObsidianNote.link(String(path.dropFirst(root.count + 1)), alias: alias)
        }
        let indexName = "Merkzettel-Index"
        let indexFile = folder.appending(path: indexName + ".md")
        var index: [ObsidianNote.IndexItem] = []

        // Text typed a moment ago is in memory only until this save.
        try? context.save()
        /// Writes a note when its content changed. A renamed project takes its note along.
        func put(_ text: String, at file: URL, was old: String) throws {
            if !old.isEmpty, old != file.path, manager.fileExists(atPath: old), !manager.fileExists(atPath: file.path) {
                try? manager.moveItem(atPath: old, toPath: file.path)
            }
            if (try? String(contentsOf: file, encoding: .utf8)) != text {
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        var used: Set<String> = []
        // No project note may take the index's name.
        var taken: Set<String> = ["merkzettel-index"]

        func note(_ entry: Entry) -> ObsidianNote.Note {
            var file: String?
            if let data = entry.imageData {
                let name = "Merkzettel-\(entry.uuid.uuidString).png"
                let target = pictures.appending(path: name)
                try? manager.createDirectory(at: pictures, withIntermediateDirectories: true)
                if !manager.fileExists(atPath: target.path) { try? data.write(to: target) }
                used.insert(name)
                file = name
            }
            return ObsidianNote.Note(text: entry.text, imageFile: file)
        }
        func task(_ entry: Entry, archived: Bool) -> ObsidianNote.Task {
            ObsidianNote.Task(title: entry.text, due: entry.dueDate?.formatted(day),
                              done: archived ? (entry.archivedAt ?? .now).formatted(day) : nil,
                              notes: (archived ? entry.allNotes : entry.openNotes).map(note))
        }

        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for project in projects {
                // Two projects of one name get "Name" and "Name 2".
                let base = ObsidianNote.fileName(project.name)
                var name = base
                var number = 2
                while taken.contains(name.lowercased()) {
                    name = "\(base) \(number)"
                    number += 1
                }
                taken.insert(name.lowercased())
                let file = folder.appending(path: name + ".md")
                let archiveName = name + " Archiv"
                let archiveFile = archiveFolder.appending(path: archiveName + ".md")
                let archive = project.archive
                // The archive note exists once something was archived, and stays from then on.
                let hasArchiveNote = includeArchive && (!archive.isEmpty || !project.obsidianArchive.isEmpty)
                let text = ObsidianNote.markdown(
                    project: project.name, folder: project.hasFolder ? project.folderPath : nil,
                    open: project.entries(.todo).map { task($0, archived: false) },
                    loose: project.looseNotes.map(note),
                    archiveNote: hasArchiveNote ? link(archiveFile, alias: archiveName) : nil,
                    indexNote: link(indexFile, alias: indexName)
                )
                index.append(ObsidianNote.IndexItem(link: link(file, alias: name), openTasks: project.entries(.todo).count))
                try put(text, at: file, was: project.obsidianNote)
                if project.obsidianNote != file.path { project.obsidianNote = file.path }
                if hasArchiveNote {
                    try manager.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
                    let archiveText = ObsidianNote.archiveMarkdown(
                        project: project.name, projectNote: link(file, alias: name),
                        archived: archive.filter { $0.kind == .todo }.map { task($0, archived: true) },
                        finished: archive.filter { $0.kind == .note }.map {
                            ObsidianNote.FinishedNote(note: note($0), taskTitle: $0.parent?.text, done: ($0.archivedAt ?? .now).formatted(day))
                        }
                    )
                    try put(archiveText, at: archiveFile, was: project.obsidianArchive)
                    if project.obsidianArchive != archiveFile.path { project.obsidianArchive = archiveFile.path }
                }
            }
            let parent = URL(fileURLWithPath: obsidianParent)
            let parentLink = !obsidianParent.isEmpty && manager.fileExists(atPath: parent.path)
                ? link(parent, alias: parent.deletingPathExtension().lastPathComponent) : nil
            try put(ObsidianNote.indexMarkdown(parentLink: parentLink, projects: index), at: indexFile, was: "")
            try? context.save()
            // Pictures no note shows any more go away. Only the app's own files are touched.
            for name in (try? manager.contentsOfDirectory(atPath: pictures.path)) ?? []
            where name.hasPrefix("Merkzettel-") && name.hasSuffix(".png") && !used.contains(name) {
                try? manager.removeItem(at: pictures.appending(path: name))
            }
            obsidianFailed = false
            obsidianStatus = "Zuletzt geschrieben: \(Date.now.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "de_DE"))))"
        } catch {
            obsidianFailed = true
            obsidianStatus = "Schreiben in den Vault ist fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Shows the project's note in Obsidian.
    func openInObsidian(_ project: Project) {
        guard let file = obsidianFile(for: project) else { return }
        writeObsidian()
        var link = URLComponents(string: "obsidian://open")
        link?.queryItems = [URLQueryItem(name: "path", value: project.obsidianNote.isEmpty ? file.path : project.obsidianNote)]
        if let url = link?.url { NSWorkspace.shared.open(url) }
    }

    // MARK: Projects

    var projects: [Project] {
        (try? context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))) ?? []
    }

    var project: Project? { projects.first { $0.id == projectID } }

    /// Adds a project and selects it. Without a name, the sidebar starts renaming it.
    @discardableResult
    func addProject(name: String = "", folder: URL? = nil) -> Project {
        let project = Project(name: ListParser.projectName(name))
        project.folderPath = folder?.path ?? ""
        project.sortIndex = (projects.map(\.sortIndex).max() ?? -1) + 1
        context.insert(project)
        save()
        page = .open
        showsAgenda = false
        projectID = project.id
        if name.isEmpty { renamingID = project.id } else { ensureFolder(for: project) }
        return project
    }

    // MARK: Project folders and the archive file

    /// Where new projects get their folder. Empty when Settings names none.
    var rootPath: String {
        rootOverride ?? (Store.isOverridden ? "" : UserDefaults.standard.string(forKey: "projectRoot") ?? "")
    }

    private var writesArchiveFile: Bool {
        Store.isOverridden || UserDefaults.standard.object(forKey: "archiveFile") as? Bool ?? true
    }

    /// Gives a project without a folder one inside the root folder, named like the project.
    func ensureFolder(for project: Project) {
        guard !project.hasFolder, !rootPath.isEmpty else { return }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let base = ArchiveDocument.folderName(project.name)
        var name = base
        var number = 2
        // Another project may own the folder of that name already.
        while projects.contains(where: { $0.folderPath == root.appending(path: name).path }) {
            name = "\(base) \(number)"
            number += 1
        }
        let url = root.appending(path: name, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            project.folderPath = url.path
            save()
            writeArchiveFile(for: project)
        } catch {
            folderProblem = "Der Ordner „\(url.path)“ konnte nicht angelegt werden: \(error.localizedDescription)"
        }
    }

    /// Writes the archive as Merkzettel-Archiv.md into the project folder, pictures beside it.
    func writeArchiveFile(for project: Project?) {
        guard let project, project.hasFolder, writesArchiveFile else { return }
        let folder = URL(fileURLWithPath: project.folderPath, isDirectory: true)
        let file = folder.appending(path: ArchiveDocument.fileName)
        let manager = FileManager.default
        let archive = project.archive
        // No file for a project that never archived anything.
        guard manager.fileExists(atPath: folder.path), !archive.isEmpty || manager.fileExists(atPath: file.path) else { return }

        let pictures = folder.appending(path: ArchiveDocument.imageFolder, directoryHint: .isDirectory)
        var used: Set<String> = []
        func picture(_ entry: Entry) -> String? {
            guard let data = entry.imageData else { return nil }
            let name = "\(entry.uuid.uuidString).png"
            let target = pictures.appending(path: name)
            try? manager.createDirectory(at: pictures, withIntermediateDirectories: true)
            if !manager.fileExists(atPath: target.path) { try? data.write(to: target) }
            used.insert(name)
            return "\(ArchiveDocument.imageFolder)/\(name)"
        }
        let dayFormat = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Locale(identifier: "de_DE"))
        func date(_ entry: Entry) -> String {
            (entry.archivedAt ?? .now).formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute().locale(Locale(identifier: "de_DE")))
        }
        let items = archive.map { entry in
            ArchiveDocument.Item(
                title: entry.text, isTask: entry.kind == .todo, date: date(entry), due: entry.dueDate?.formatted(dayFormat),
                taskTitle: entry.kind == .note ? entry.parent?.text : nil,
                imageFile: entry.kind == .note ? picture(entry) : nil,
                notes: entry.allNotes.map { ArchiveDocument.Note(text: $0.text, imageFile: picture($0)) }
            )
        }
        do {
            try ArchiveDocument.markdown(project: project.name, items: items).write(to: file, atomically: true, encoding: .utf8)
        } catch {
            folderProblem = "Die Archiv-Datei in „\(folder.path)“ konnte nicht geschrieben werden: \(error.localizedDescription)"
        }
        // Pictures of entries that left the archive go away. Only the app's own folder is touched.
        for name in (try? manager.contentsOfDirectory(atPath: pictures.path)) ?? [] where name.hasSuffix(".png") && !used.contains(name) {
            try? manager.removeItem(at: pictures.appending(path: name))
        }
    }

    /// One project per folder, named like the folder. A folder that is a project already gets selected.
    func addFolders(_ urls: [URL]) {
        for url in urls {
            if let known = projects.first(where: { $0.folderPath == url.path }) {
                projectID = known.id
            } else {
                addProject(name: url.lastPathComponent, folder: url)
            }
        }
    }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Als Projekt hinzufügen"
        panel.message = "Wähle einen oder mehrere Projektordner."
        if panel.runModal() == .OK { addFolders(panel.urls) }
    }

    func showInFinder(_ project: Project) {
        guard project.hasFolder else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.folderPath)
    }

    func finishRenaming(_ project: Project) {
        project.name = ListParser.projectName(project.name)
        if renamingID == project.id { renamingID = nil }
        save()
        ensureFolder(for: project)
    }

    func moveProjects(from source: IndexSet, to destination: Int) {
        var ordered = projects
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, project) in ordered.enumerated() { project.sortIndex = index }
        save()
    }

    /// Deletes the project with all its entries. The Finder folder stays untouched.
    func delete(_ project: Project) {
        let wasSelected = project.id == projectID
        context.delete(project)
        save()
        if wasSelected { projectID = projects.first?.id }
    }

    // MARK: Keyboard

    /// Text fields report when they take or lose the cursor.
    func fieldFocus(_ id: String, _ focused: Bool) {
        if focused { focusedField = id } else if focusedField == id { focusedField = nil }
    }

    /// Shift-Return in a task or note field means "on to a note line". A text
    /// field would treat it as a plain Return, so the key is caught before it gets there.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
            guard let self else { return event }
            // Command-V with a picture on the clipboard: a text field would
            // ignore it, so the picture goes into the note instead.
            if event.charactersIgnoringModifiers?.lowercased() == "v", modifiers == .command, self.pastePicture() { return nil }
            // Option-Command-Left and -Right step through the notes in a large note window.
            if event.keyCode == 123 || event.keyCode == 124, modifiers == [.command, .option], self.frontNote != nil {
                self.noteStepOffset = event.keyCode == 123 ? -1 : 1
                self.noteStepTick += 1
                return nil
            }
            // Up and Down walk through the tasks, notes, and add lines of the list.
            // Inside a text of several lines they first move within the text.
            if event.keyCode == 125 || event.keyCode == 126, modifiers.isEmpty, self.focusedField != nil,
               let editor = event.window?.firstResponder as? NSTextView, !editor.hasMarkedText() {
                let text = editor.string as NSString
                let selection = editor.selectedRange()
                let down = event.keyCode == 125
                let rest = down ? text.substring(from: min(NSMaxRange(selection), text.length)) : text.substring(to: min(selection.location, text.length))
                if !rest.contains("\n"), self.moveFocus(by: down ? 1 : -1) { return nil }
                return event
            }
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            guard isReturn, modifiers == .shift, self.focusedField != nil else { return event }
            self.shiftReturn += 1
            return nil
        }
    }

    /// The picture on the clipboard, unless the clipboard holds text to paste.
    /// A web address beside the picture (from a browser) does not count as text.
    private var clipboardPicture: Data? {
        let board = NSPasteboard.general
        guard let png = ImageTools.png(from: board) else { return nil }
        if let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
           !(text.hasPrefix("http") || text.hasPrefix("file:")) || text.contains(where: \.isWhitespace) {
            return nil
        }
        return png
    }

    private func entry(_ uuid: UUID) -> Entry? {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Puts the clipboard picture where the cursor is: into a text note that has
    /// no picture yet (its text becomes the caption), else as a new picture note
    /// of the task. In the large note window the window shows the result. False
    /// when there is no picture or no place for it, so Command-V works as usual.
    @discardableResult
    func pastePicture() -> Bool {
        let target: Entry?
        if let field = focusedField {
            if field.hasPrefix("add-") {
                target = UUID(uuidString: String(field.dropFirst(4))).flatMap(entry)
            } else {
                target = UUID(uuidString: field).flatMap(entry)
            }
        } else if let front = frontNote {
            target = entry(front)
        } else {
            target = nil
        }
        guard let target, let png = clipboardPicture, ImageTools.pixelSize(png) != nil else { return false }
        if target.kind == .note, !target.hasImage {
            target.imageData = png
            target.thumbnail = ImageTools.thumbnail(png) ?? png
            activeNote = target.uuid
            save()
            return true
        }
        let task = target.kind == .todo ? target : target.parent
        guard let task, let project = task.project, let added = addImage(png, to: project, under: task) else { return false }
        activeNote = added.uuid
        return true
    }

    /// The note Command-Return opens large. In a "Notiz hinzufügen" line, or in
    /// the title of a task without notes, it first adds the note (with what is
    /// typed so far, maybe nothing), so the large window has one to show. An
    /// empty note goes away again when its window closes.
    func noteToOpen() -> UUID? {
        guard let field = focusedField else { return activeNote }
        let isAddLine = field.hasPrefix("add-")
        guard let task = UUID(uuidString: isAddLine ? String(field.dropFirst(4)) : field).flatMap(entry) else { return activeNote }
        if task.kind == .note { return task.uuid }
        if !isAddLine, let first = task.openNotes.first { return first.uuid }
        guard let project = task.project else { return activeNote }
        let draft = (addDrafts["add-\(task.uuid.uuidString)"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let note = Entry(text: draft, kind: .note)
        note.sortIndex = (task.notes.map(\.sortIndex).max() ?? -1) + 1
        context.insert(note)
        project.entries.append(note)
        task.notes.append(note)
        save()
        takenDraft = "add-\(task.uuid.uuidString)"
        addDrafts[takenDraft!] = nil
        draftTaken += 1
        activeNote = note.uuid
        return note.uuid
    }

    /// The ids of the text fields of the open list from top to bottom: per task
    /// its title, its notes, its "Notiz hinzufügen" line; then "Neue Aufgabe"; then loose notes.
    func fieldOrder(of project: Project) -> [String] {
        project.entries(.todo).flatMap { task in
            [task.uuid.uuidString] + task.openNotes.map(\.uuid.uuidString) + ["add-\(task.uuid.uuidString)"]
        } + ["new-task"] + project.looseNotes.map(\.uuid.uuidString)
    }

    /// Moves the cursor to the field above or below the one that has it. False at the ends.
    @discardableResult
    func moveFocus(by offset: Int) -> Bool {
        // A move that is still under way counts from where it is going, so
        // fast presses and a held key do not get lost.
        guard !showsAgenda, page == .open, let project, let current = focusRequest ?? focusedField else { return false }
        let order = fieldOrder(of: project)
        guard let index = order.firstIndex(of: current), order.indices.contains(index + offset) else { return false }
        focusRequest = order[index + offset]
        return true
    }

    /// The open notes of the note's project in reading order: task by task in
    /// priority order, then the notes without a task. The large note window steps through them.
    func noteSequence(for note: Entry) -> [Entry] {
        guard let project = note.project else { return [note] }
        return project.entries(.todo).flatMap(\.openNotes) + project.looseNotes
    }

    // MARK: Entries

    /// Adds entries to the project. Several lines become several tasks; a note
    /// stays one note and goes below its task.
    @discardableResult
    func add(_ text: String, kind: EntryKind, to project: Project, under task: Entry? = nil) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let texts = kind == .todo ? ListParser.items(text) : (trimmed.isEmpty ? [] : [trimmed])
        let siblings = kind == .note && task != nil ? task?.notes ?? [] : project.entries(kind)
        var next = (siblings.map(\.sortIndex).max() ?? -1) + 1
        for text in texts {
            let entry = Entry(text: text, kind: kind)
            entry.sortIndex = next
            next += 1
            context.insert(entry)
            project.entries.append(entry)
            if kind == .note, let task { task.notes.append(entry) }
        }
        save()
        return texts.count
    }

    /// Adds a picture (PNG data) as a note below the task.
    @discardableResult
    func addImage(_ png: Data, to project: Project, under task: Entry) -> Entry? {
        guard ImageTools.pixelSize(png) != nil else { return nil }
        let entry = Entry(text: "", kind: .note)
        entry.imageData = png
        entry.thumbnail = ImageTools.thumbnail(png) ?? png
        entry.sortIndex = (task.notes.map(\.sortIndex).max() ?? -1) + 1
        context.insert(entry)
        project.entries.append(entry)
        task.notes.append(entry)
        save()
        return entry
    }

    /// For drops, which arrive off the main thread and may only carry an id.
    func addImage(_ png: Data, underTaskWithID id: PersistentIdentifier) {
        guard let task = context.model(for: id) as? Entry, let project = task.project else { return }
        addImage(png, to: project, under: task)
    }

    /// The picture on the clipboard if there is one, otherwise picture files the person chooses.
    func insertImage(to project: Project, under task: Entry) {
        if let png = ImageTools.png(from: .general) {
            addImage(png, to: project, under: task)
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.prompt = "Einfügen"
        panel.message = "In der Zwischenablage ist kein Bild. Wähle Bilddateien."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let png = ImageTools.png(fromFile: url) { addImage(png, to: project, under: task) }
        }
    }

    /// Opens the picture in the Mac's image viewer.
    func openImage(_ entry: Entry) {
        guard let data = entry.imageData else { return }
        let file = URL.temporaryDirectory.appending(path: "Merkzettel-\(entry.uuid.uuidString).png")
        try? data.write(to: file)
        NSWorkspace.shared.open(file)
    }

    func copyImage(_ entry: Entry) {
        guard let data = entry.imageData, let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    /// Every line on the clipboard becomes a task in the current project.
    func pasteList() {
        guard let project, let text = NSPasteboard.general.string(forType: .string) else { return }
        page = .open
        add(text, kind: .todo, to: project)
    }

    /// Sets or removes the due date of a task.
    func setDue(_ entry: Entry, _ date: Date?) {
        entry.dueDate = date.map { Calendar.current.startOfDay(for: $0) }
        save()
    }

    /// Open tasks with a due date from every project, soonest first.
    var agenda: [Entry] {
        let dated = FetchDescriptor<Entry>(predicate: #Predicate { !$0.isArchived && $0.dueDate != nil && $0.kindRaw == "todo" },
                                           sortBy: [SortDescriptor(\.dueDate), SortDescriptor(\.sortIndex)])
        return (try? context.fetch(dated)) ?? []
    }

    /// Leaves "Termine" and shows the task in its project.
    func showInProject(_ entry: Entry) {
        guard let project = entry.project else { return }
        showsAgenda = false
        page = .open
        projectID = project.id
        highlightUUID = entry.uuid
    }

    /// Done tasks and finished notes move to the archive.
    func archive(_ entry: Entry) {
        entry.isArchived = true
        entry.archivedAt = .now
        save()
        writeArchiveFile(for: entry.project)
    }

    /// Back to the end of its open list.
    func restore(_ entry: Entry) {
        entry.sortIndex = (entry.project?.entries(entry.kind).map(\.sortIndex).max() ?? -1) + 1
        entry.isArchived = false
        entry.archivedAt = nil
        save()
        writeArchiveFile(for: entry.project)
    }

    /// A note becomes a task of its own, at the end of the list.
    func makeTask(_ note: Entry) {
        guard note.kind == .note else { return }
        note.sortIndex = (note.project?.entries(.todo).map(\.sortIndex).max() ?? -1) + 1
        note.parent = nil
        note.kind = .todo
        save()
    }

    /// An entry edited down to nothing goes away. A picture needs no caption.
    func finishEditing(_ entry: Entry) {
        entry.text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.text.isEmpty, !entry.hasImage { context.delete(entry) }
        save()
    }

    func delete(_ entry: Entry) {
        let project = entry.project
        let wasInArchive = entry.isArchived || entry.parent?.isArchived == true
        if activeNote == entry.uuid { activeNote = nil }
        context.delete(entry)
        save()
        if wasInArchive { writeArchiveFile(for: project) }
    }

    func move(_ kind: EntryKind, in project: Project, from source: IndexSet, to destination: Int) {
        var ordered = project.entries(kind)
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in ordered.enumerated() { entry.sortIndex = index }
        save()
    }

    /// Moves the dragged task to the place of the task it was dropped on.
    @discardableResult
    func moveTask(withUUID uuid: String, onto target: Entry) -> Bool {
        guard let project = target.project else { return false }
        var ordered = project.entries(.todo)
        guard let from = ordered.firstIndex(where: { $0.uuid.uuidString == uuid }),
              let to = ordered.firstIndex(where: { $0.id == target.id }), from != to else { return false }
        ordered.insert(ordered.remove(at: from), at: to)
        for (index, entry) in ordered.enumerated() { entry.sortIndex = index }
        save()
        return true
    }

    /// Text dropped on a task: a dragged task changes the priority, any other text becomes a note.
    func dropText(_ text: String, onTaskWithID id: PersistentIdentifier) {
        guard let task = context.model(for: id) as? Entry, let project = task.project else { return }
        if UUID(uuidString: text) != nil {
            moveTask(withUUID: text, onto: task)
        } else {
            add(text, kind: .note, to: project, under: task)
        }
    }

    func clearArchive(of project: Project) {
        for entry in project.archive { context.delete(entry) }
        save()
        writeArchiveFile(for: project)
    }
}

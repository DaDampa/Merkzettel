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
    var projectToDelete: Project?
    /// The task whose circle was clicked. An alert asks before it goes to the archive.
    var taskToComplete: Entry?
    /// The task to scroll to and mark for a moment, after a jump from "Termine".
    var highlightUUID: UUID?
    /// Shown as an alert when a project folder or the archive file cannot be written.
    var folderProblem: String?
    /// Replaces the root folder from Settings in the self-test.
    @ObservationIgnored var rootOverride: String?
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
    }

    private var context: ModelContext { container.mainContext }

    private func persist(_ value: Any, _ key: String) {
        if !Store.isOverridden { UserDefaults.standard.set(value, forKey: key) }
    }

    private func save() { try? context.save() }

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

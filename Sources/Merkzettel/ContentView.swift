import SwiftData
import MerkzettelKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Query(sort: [SortDescriptor(\Project.sortIndex), SortDescriptor(\Project.createdAt)]) private var projects: [Project]
    @AppStorage("allSpaces") private var allSpaces = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            ProjectSidebar(projects: projects)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
        } detail: {
            if model.showsAgenda {
                AgendaPage()
            } else if let project = projects.first(where: { $0.id == model.projectID }) {
                ProjectPage(project: project)
            } else {
                ContentUnavailableView {
                    Label("Kein Projekt", systemImage: "folder.badge.plus")
                } description: {
                    Text("Lege ein Projekt an oder wähle einen bestehenden Projektordner.")
                } actions: {
                    Button("Neues Projekt") { model.addProject() }
                    Button("Ordner wählen …") { model.chooseFolders() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WindowLevel(floating: model.alwaysOnTop, allSpaces: allSpaces))
        .confirmationDialog(
            "„\(model.projectToDelete?.name ?? "")“ löschen?",
            isPresented: Binding(get: { model.projectToDelete != nil }, set: { if !$0 { model.projectToDelete = nil } })
        ) {
            Button("Projekt löschen", role: .destructive) {
                if let project = model.projectToDelete { model.delete(project) }
                model.projectToDelete = nil
            }
            Button("Abbrechen", role: .cancel) { model.projectToDelete = nil }
        } message: {
            Text("Alle Aufgaben und Notizen des Projekts werden gelöscht, auch das Archiv. Der Ordner im Finder bleibt.")
        }
        .alert("Aufgabe erledigt?", isPresented: Binding(get: { model.taskToComplete != nil }, set: { if !$0 { model.taskToComplete = nil } })) {
            Button("Erledigt") {
                if let task = model.taskToComplete { withAnimation { model.archive(task) } }
                model.taskToComplete = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Abbrechen", role: .cancel) { model.taskToComplete = nil }
        } message: {
            Text("„\(model.taskToComplete?.text ?? "")“ wandert mit allen Notizen ins Archiv. Von dort lässt sie sich zurückholen.")
        }
        .alert("Ordner nicht verfügbar", isPresented: Binding(get: { model.folderProblem != nil }, set: { if !$0 { model.folderProblem = nil } })) {
            Button("OK") { model.folderProblem = nil }
        } message: {
            Text(model.folderProblem ?? "")
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
            // Adds notes while the window is open, to check that a task's block grows.
            if Store.isOverridden, ProcessInfo.processInfo.environment["APP_ADD_NOTES"] == "1",
               let project = model.project, let task = project.entries(.todo).first {
                for number in 3...5 {
                    try? await Task.sleep(for: .seconds(0.7))
                    model.add("Notiz Nummer \(number), später dazugekommen", kind: .note, to: project, under: task)
                }
            }
            // Opens the "done?" alert, or jumps from Termine to the last dated task, to look at both.
            if Store.isOverridden, ProcessInfo.processInfo.environment["APP_ASK_DONE"] == "1" {
                model.taskToComplete = model.project?.entries(.todo).first
            }
            if Store.isOverridden, ProcessInfo.processInfo.environment["APP_JUMP"] == "1", let task = model.agenda.first(where: { $0.text.hasPrefix("Abnahme") }) {
                model.showsAgenda = true
                try? await Task.sleep(for: .seconds(1))
                model.showInProject(task)
            }
            if Store.isOverridden, ProcessInfo.processInfo.environment["APP_OPEN_NOTE"] == "1",
               let note = model.project?.entries(.todo).first?.openNotes.first {
                openWindow(id: "note", value: note.uuid)
            }
        }
    }
}

/// What the sidebar can select: the dated tasks of all projects, or one project.
enum SidebarSelection: Hashable {
    case agenda
    case project(PersistentIdentifier)
}

struct ProjectSidebar: View {
    @Environment(AppModel.self) private var model
    let projects: [Project]

    private var selection: Binding<SidebarSelection?> {
        Binding {
            model.showsAgenda ? .agenda : model.projectID.map { .project($0) }
        } set: { value in
            switch value {
            case .agenda: model.showsAgenda = true
            case .project(let id):
                model.showsAgenda = false
                model.projectID = id
            case nil: break
            }
        }
    }

    var body: some View {
        List(selection: selection) {
            AgendaSidebarRow()
                .tag(SidebarSelection.agenda)
            Section("Projekte") {
                ForEach(projects) { project in
                    ProjectRow(project: project)
                        .tag(SidebarSelection.project(project.id))
                }
                .onMove { model.moveProjects(from: $0, to: $1) }
            }
        }
        .safeAreaInset(edge: .bottom, alignment: .leading) {
            Menu {
                Button("Neues Projekt", systemImage: "plus") { model.addProject() }
                Button("Bestehenden Ordner wählen …", systemImage: "folder") { model.chooseFolders() }
            } label: {
                Label("Projekt", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(Space.md)
            .help("Projekt anlegen oder Ordner wählen")
        }
    }
}

/// "Termine" in the sidebar. The badge counts what is due today or overdue.
struct AgendaSidebarRow: View {
    @Query(filter: Entry.openDatedTasks) private var dated: [Entry]

    var body: some View {
        let urgent = dated.filter { Agenda.bucket(for: $0.dueDate ?? .distantFuture).rawValue <= Agenda.Bucket.today.rawValue }.count
        Label("Termine", systemImage: "calendar")
            .badge(urgent)
            .help("Alle Aufgaben mit Datum, über alle Projekte")
    }
}

/// Every open task with a due date, grouped by how soon it is due.
struct AgendaPage: View {
    @Environment(AppModel.self) private var model
    @Query(filter: Entry.openDatedTasks) private var unsorted: [Entry]

    var body: some View {
        @Bindable var model = model
        let dated = unsorted.sorted { ($0.dueDate ?? .distantFuture, $0.sortIndex) < ($1.dueDate ?? .distantFuture, $1.sortIndex) }
        List {
            ForEach(Agenda.Bucket.allCases) { bucket in
                let tasks = dated.filter { Agenda.bucket(for: $0.dueDate ?? .distantFuture) == bucket }
                if !tasks.isEmpty {
                    Section(bucket.title) {
                        ForEach(tasks) { task in
                            AgendaRow(task: task, overdue: bucket == .overdue)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if dated.isEmpty {
                ContentUnavailableView(
                    "Keine Termine",
                    systemImage: "calendar",
                    description: Text("Gib einer Aufgabe über das Kalender-Symbol ein Datum. Sie erscheint dann hier.")
                )
            }
        }
        .navigationTitle("Termine")
        .navigationSubtitle("\(dated.count) Aufgaben mit Datum")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $model.alwaysOnTop) {
                    Label("Immer im Vordergrund", systemImage: model.alwaysOnTop ? "pin.fill" : "pin")
                }
                .help("Fenster immer im Vordergrund halten (Umschalt-Command-T)")
            }
        }
    }
}

struct AgendaRow: View {
    @Environment(AppModel.self) private var model
    let task: Entry
    let overdue: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Button("Erledigt", systemImage: "circle") { model.taskToComplete = task }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Als erledigt markieren (mit Rückfrage)")
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(task.text)
                    .font(.headline)
                    .lineLimit(2)
                Text(task.project?.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let due = task.dueDate {
                Text(due, format: .dateTime.weekday(.abbreviated).day().month())
                    .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(.rect)
        .onTapGesture { model.showInProject(task) }
        .help("Klick springt zur Aufgabe in ihrem Projekt")
        .contextMenu {
            Button("Im Projekt zeigen", systemImage: "arrow.right.circle") { model.showInProject(task) }
            Button("Erledigt …", systemImage: "archivebox") { model.taskToComplete = task }
            Button("Datum entfernen", systemImage: "calendar.badge.minus") { model.setDue(task, nil) }
        }
    }
}

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    @Bindable var project: Project
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if model.renamingID == project.id {
                TextField("Projektname", text: $project.name)
                    .focused($nameFocused)
                    .onAppear { nameFocused = true }
                    .onSubmit { model.finishRenaming(project) }
                    .onChange(of: nameFocused) { if !nameFocused { model.finishRenaming(project) } }
            } else {
                Label(project.name, systemImage: project.hasFolder ? "folder" : "tray.full")
                    .badge(project.entries(.todo).count)
                    .help(project.hasFolder ? project.folderPath : project.name)
            }
        }
        .contextMenu {
            Button("Umbenennen", systemImage: "pencil") { model.renamingID = project.id }
            if project.hasFolder {
                Button("Im Finder zeigen", systemImage: "folder") { model.showInFinder(project) }
            } else if !model.rootPath.isEmpty {
                Button("Projektordner anlegen", systemImage: "folder.badge.plus") { model.ensureFolder(for: project) }
            }
            Divider()
            Button("Projekt löschen …", systemImage: "trash", role: .destructive) { model.projectToDelete = project }
        }
    }
}

struct ProjectPage: View {
    @Environment(AppModel.self) private var model
    let project: Project

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.page {
            case .open: OpenList(project: project)
            case .archive: ArchiveList(project: project)
            }
        }
        .navigationTitle(project.name)
        .navigationSubtitle("\(project.entries(.todo).count) Aufgaben")
        .toolbar {
            ToolbarItem {
                Picker("Ansicht", selection: $model.page) {
                    ForEach(Page.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Offene Einträge oder Archiv (Umschalt-Command-A)")
            }
            ToolbarItem {
                Toggle(isOn: $model.alwaysOnTop) {
                    Label("Immer im Vordergrund", systemImage: model.alwaysOnTop ? "pin.fill" : "pin")
                }
                .help("Fenster immer im Vordergrund halten (Umschalt-Command-T)")
            }
        }
        .confirmationDialog("Archiv von „\(project.name)“ leeren?", isPresented: $model.confirmClearArchive) {
            Button("Archiv leeren", role: .destructive) { model.clearArchive(of: project) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle archivierten Aufgaben und Notizen dieses Projekts werden gelöscht, auch aus der Archiv-Datei im Projektordner.")
        }
    }
}

/// Tasks as headings in priority order, each with its notes below.
struct OpenList: View {
    @Environment(AppModel.self) private var model
    let project: Project

    var body: some View {
        let loose = project.looseNotes
        // A plain stack, not a List: a List row keeps its height while a text
        // field in it is being edited, so a task's block could not grow.
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(project.entries(.todo)) { todo in
                    TodoBlock(project: project, todo: todo)
                        .id(todo.uuid)
                    Divider()
                }
                AddField(project: project, task: nil)
                    .padding(.vertical, Space.xs)
                if !loose.isEmpty {
                    Text("Notizen ohne Aufgabe")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, Space.md)
                    ForEach(loose) { NoteRow(note: $0) }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.md)
        }
        .onAppear { jump(proxy) }
        .onChange(of: model.highlightUUID) { jump(proxy) }
        }
    }
}

extension OpenList {
    /// After a click in "Termine": scrolls to the task and marks it for a moment.
    fileprivate func jump(_ proxy: ScrollViewProxy) {
        guard let target = model.highlightUUID else { return }
        Task {
            // The list has to be laid out before it can scroll.
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation { proxy.scrollTo(target, anchor: .center) }
            try? await Task.sleep(for: .seconds(1.6))
            if model.highlightUUID == target { withAnimation { model.highlightUUID = nil } }
        }
    }
}

/// One task with its notes. Dragging its handle onto another task changes the priority.
struct TodoBlock: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let todo: Entry
    @State private var dropTargeted = false

    /// Picture files from the Finder, pictures dragged out of another app, a
    /// dragged task (its id as text), or text that becomes a note.
    private func drop(_ providers: [NSItemProvider]) {
        let model = model, taskID = todo.id
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let png = ImageTools.png(fromFile: url), NSBitmapImageRep(data: png) != nil else { return }
                    Task { @MainActor in model.addImage(png, underTaskWithID: taskID) }
                }
            } else if !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in withAnimation { model.dropText(text, onTaskWithID: taskID) } }
                }
            } else {
                _ = provider.loadDataRepresentation(for: .image) { data, _ in
                    guard let data, let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return }
                    Task { @MainActor in model.addImage(png, underTaskWithID: taskID) }
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Button("Erledigt", systemImage: "circle") { model.taskToComplete = todo }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Als erledigt markieren (mit Rückfrage)")
                EntryField(entry: todo)
                    .font(.headline)
                DueField(task: todo)
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .padding(Space.xs)
                    .contentShape(.rect)
                    .draggable(todo.uuid.uuidString) {
                        Text(todo.text)
                            .font(.headline)
                            .padding(Space.sm)
                    }
                    .help("Hier anfassen und auf eine andere Aufgabe ziehen, um die Priorität zu ändern")
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(todo.openNotes) { NoteRow(note: $0) }
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    AddField(project: project, task: todo)
                    Button("Bild einfügen", systemImage: "photo.badge.plus") { model.insertImage(to: project, under: todo) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Bild aus der Zwischenablage einfügen, sonst Bilddatei wählen")
                }
            }
            .padding(.leading, Space.xxl)
        }
        .padding(.vertical, Space.xs)
        .background(dropTargeted || model.highlightUUID == todo.uuid ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: Space.sm))
        .onDrop(of: [.fileURL, .image, .plainText], isTargeted: $dropTargeted) { providers in
            drop(providers)
            return true
        }
        .contextMenu {
            Button("Erledigt …", systemImage: "archivebox") { model.taskToComplete = todo }
            Button("Bild einfügen", systemImage: "photo.badge.plus") { model.insertImage(to: project, under: todo) }
            if todo.dueDate == nil {
                Button("Datum setzen", systemImage: "calendar.badge.plus") { model.setDue(todo, .now) }
            } else {
                Button("Datum entfernen", systemImage: "calendar.badge.minus") { model.setDue(todo, nil) }
            }
            Divider()
            Button("Aufgabe mit Notizen löschen", systemImage: "trash", role: .destructive) { model.delete(todo) }
        }
    }
}

/// The due date of a task: a calendar button while there is none, then a date field.
struct DueField: View {
    @Environment(AppModel.self) private var model
    let task: Entry

    var body: some View {
        if let due = task.dueDate {
            HStack(spacing: Space.xs) {
                if Agenda.bucket(for: due) == .overdue {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .help("Überfällig")
                        .accessibilityLabel("Überfällig")
                }
                DatePicker("Termin", selection: Binding(get: { due }, set: { model.setDue(task, $0) }), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    // Day first, like the rest of the German interface.
                    .environment(\.locale, Locale(identifier: "de_DE"))
                    .fixedSize()
                    .help("Termin ändern. Entfernen per Rechtsklick auf die Aufgabe.")
            }
        } else {
            Button("Datum setzen", systemImage: "calendar.badge.plus") { model.setDue(task, .now) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Termin setzen")
        }
    }
}

struct NoteRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let note: Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: note.hasImage ? "photo" : "note.text")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            if note.hasImage {
                VStack(alignment: .leading, spacing: Space.xs) {
                    NoteImage(note: note, maxHeight: 160)
                        .onTapGesture(count: 2) { model.openImage(note) }
                        .help("Doppelklick öffnet das Bild groß")
                    EntryField(entry: note, placeholder: "Bildunterschrift")
                        .font(.callout)
                }
            } else {
                EntryField(entry: note, lines: 3)
            }
            Button("Groß öffnen", systemImage: "arrow.up.left.and.arrow.down.right") { openWindow(id: "note", value: note.uuid) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Notiz in einem eigenen Fenster öffnen")
            Button("Abschließen", systemImage: "archivebox") { withAnimation { model.archive(note) } }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Notiz abschließen: ins Archiv")
        }
        .contextMenu {
            Button("Groß öffnen", systemImage: "arrow.up.left.and.arrow.down.right") { openWindow(id: "note", value: note.uuid) }
            Button("Abschließen", systemImage: "archivebox") { model.archive(note) }
            if note.hasImage {
                Button("Bild öffnen", systemImage: "arrow.up.forward.app") { model.openImage(note) }
                Button("Bild kopieren", systemImage: "doc.on.doc") { model.copyImage(note) }
            } else {
                Button("In Aufgabe umwandeln", systemImage: "arrow.up.left") { model.makeTask(note) }
            }
            Divider()
            Button("Notiz löschen", systemImage: "trash", role: .destructive) { model.delete(note) }
        }
    }
}

/// One note in a window of its own, with room for long text.
struct NoteWindow: View {
    @Environment(AppModel.self) private var model
    @Query private var notes: [Entry]
    @AppStorage("allSpaces") private var allSpaces = false

    init(uuid: UUID) {
        _notes = Query(filter: #Predicate<Entry> { $0.uuid == uuid })
    }

    var body: some View {
        Group {
            if let note = notes.first {
                NoteEditor(note: note)
            } else {
                ContentUnavailableView("Notiz nicht mehr vorhanden", systemImage: "note.text",
                                       description: Text("Sie wurde gelöscht."))
            }
        }
        .background(WindowLevel(floating: model.alwaysOnTop, allSpaces: allSpaces))
    }
}

struct NoteEditor: View {
    @Environment(AppModel.self) private var model
    @Bindable var note: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if note.hasImage, let data = note.imageData ?? note.thumbnail, let image = NSImage(data: data) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .accessibilityLabel(note.text.isEmpty ? "Bild" : note.text)
                }
                Divider()
            }
            TextEditor(text: $note.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(Space.md)
                .frame(maxHeight: note.hasImage ? 96 : .infinity)
        }
        .navigationTitle(note.parent?.text ?? (note.hasImage ? "Bild" : "Notiz"))
        .navigationSubtitle(note.project?.name ?? "")
        .toolbar {
            if note.hasImage {
                ToolbarItem {
                    Button("Bild kopieren", systemImage: "doc.on.doc") { model.copyImage(note) }
                        .help("Bild in die Zwischenablage kopieren")
                }
            }
        }
        .onDisappear { model.finishEditing(note) }
    }
}

/// The picture of a note, never larger than it is.
struct NoteImage: View {
    let note: Entry
    let maxHeight: CGFloat

    var body: some View {
        if let data = note.thumbnail ?? note.imageData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: image.size.width, maxHeight: min(maxHeight, image.size.height), alignment: .leading)
                .clipShape(.rect(cornerRadius: Space.xs))
                .accessibilityLabel(note.text.isEmpty ? "Bild" : note.text)
        }
    }
}

/// The text of an entry, edited in place. Emptied text deletes the entry.
struct EntryField: View {
    @Environment(AppModel.self) private var model
    @Bindable var entry: Entry
    var placeholder: String?
    /// The list shows at most this many lines. Longer text scrolls, or opens large.
    var lines = 6
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder ?? entry.kind.placeholder, text: $entry.text, axis: .vertical)
            .lineLimit(1...lines)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { focused = false }
            .onChange(of: focused) { if !focused { model.finishEditing(entry) } }
    }
}

/// Type, press Return, type the next one. Without a task it adds tasks, with one it adds notes below it.
struct AddField: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let task: Entry?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(task == nil ? "Neue Aufgabe" : "Notiz hinzufügen", text: $draft)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    model.add(draft, kind: task == nil ? .todo : .note, to: project, under: task)
                    draft = ""
                    focused = true
                }
        }
        .font(task == nil ? .body : .callout)
        .onChange(of: model.focusNewTask) {
            if model.focusNewTask, task == nil {
                focused = true
                model.focusNewTask = false
            }
        }
        .onChange(of: project.id) { draft = "" }
    }
}

/// Done tasks with their notes, and notes finished on their own, newest first.
struct ArchiveList: View {
    @Environment(AppModel.self) private var model
    let project: Project

    var body: some View {
        let archive = project.archive
        List(archive) { entry in
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: entry.kind == .todo ? "checkmark.circle.fill" : "note.text")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(entry.kind == .todo ? "Aufgabe" : "Notiz")
                VStack(alignment: .leading, spacing: Space.xs) {
                    if entry.hasImage { NoteImage(note: entry, maxHeight: 96) }
                    if !entry.text.isEmpty {
                        Text(entry.text)
                            .font(entry.kind == .todo ? .headline : .body)
                            .textSelection(.enabled)
                    }
                    ForEach(entry.allNotes) { note in
                        if note.hasImage { NoteImage(note: note, maxHeight: 96) }
                        if !note.text.isEmpty {
                            Label(note.text, systemImage: "note.text")
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                    Text(caption(entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Zurückholen", systemImage: "arrow.uturn.backward") { withAnimation { model.restore(entry) } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Zurück zu den offenen Einträgen")
            }
            .padding(.vertical, Space.xs)
            .contextMenu {
                Button("Zurückholen", systemImage: "arrow.uturn.backward") { model.restore(entry) }
                Divider()
                Button("Endgültig löschen", systemImage: "trash", role: .destructive) { model.delete(entry) }
            }
        }
        .listStyle(.inset)
        .overlay {
            if archive.isEmpty {
                ContentUnavailableView(
                    "Archiv ist leer",
                    systemImage: "archivebox",
                    description: Text("Erledigte Aufgaben und abgeschlossene Notizen landen hier.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Archiv leeren", systemImage: "trash") { model.confirmClearArchive = true }
                    .disabled(archive.isEmpty)
                    .help("Alle archivierten Einträge dieses Projekts löschen")
            }
        }
    }

    /// "13.11.2026, 07:47", and for a single note the task it belongs to.
    private func caption(_ entry: Entry) -> String {
        let date = entry.archivedAt?.formatted(.dateTime.day().month().year().hour().minute()) ?? ""
        if entry.kind == .note, let task = entry.parent { return "\(date) · \(entry.hasImage ? "Bild" : "Notiz") zu „\(task.text)“" }
        return date
    }
}

/// Keeps the window above other apps' windows, and on every desktop if wanted.
struct WindowLevel: NSViewRepresentable {
    let floating: Bool
    let allSpaces: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let floating = floating, allSpaces = allSpaces
        // The view joins its window after this call.
        Task { @MainActor in
            guard let window = view.window else { return }
            window.level = floating ? .floating : .normal
            if allSpaces {
                window.collectionBehavior.insert(.canJoinAllSpaces)
            } else {
                window.collectionBehavior.remove(.canJoinAllSpaces)
            }
        }
    }
}

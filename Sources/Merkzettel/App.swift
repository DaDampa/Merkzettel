import AppKit
import SwiftData
import SwiftUI

// Merkzettel
//   Merkzettel                      the app
//   APP_STORE=<file> Merkzettel     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> Merkzettel   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 Merkzettel           fill an empty /tmp store with sample items (tools/snap.sh)
//   Merkzettel --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Merkzettel      run with another accent from Theme.all (UI/Theme.swift)
//   APP_OPEN_NOTE=1 Merkzettel       with a /tmp store: open the first note large, to look at that window
//   APP_GRID=1 Merkzettel           draw the 8 pt grid and the layout probes over the window

@main
struct MerkzettelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())

    var body: some Scene {
        Window("Merkzettel", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 440, minHeight: 320)
        }
        .modelContainer(model.container)
        .defaultSize(width: 640, height: 560)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Neue Aufgabe") { model.page = .open; model.focusNewTask = true }
                    .keyboardShortcut("n")
                    .disabled(model.projectID == nil)
                Button("Zeilen aus der Zwischenablage als Aufgaben einfügen") { model.pasteList() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    .disabled(model.projectID == nil)
                Divider()
                Button("Neues Projekt") { model.addProject() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Ordner als Projekt hinzufügen …") { model.chooseFolders() }
                    .keyboardShortcut("o")
                Button("Projekt in Obsidian öffnen") { if let project = model.project { model.openInObsidian(project) } }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(model.project == nil || model.obsidianVault.isEmpty || model.showsAgenda)
            }
            CommandGroup(before: .toolbar) {
                Toggle("Immer im Vordergrund", isOn: Binding(get: { model.alwaysOnTop }, set: { model.alwaysOnTop = $0 }))
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button(model.page == .archive ? "Offene Einträge zeigen" : "Archiv zeigen") {
                    model.page = model.page == .archive ? .open : .archive
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
            }
        }

        // A note opened large, in a window of its own beside the compact list.
        WindowGroup("Notiz", id: "note", for: UUID.self) { $uuid in
            NoteWindow(uuid: uuid ?? UUID())
                .environment(model)
                .themed()
                .frame(minWidth: 380, minHeight: 260)
        }
        .modelContainer(model.container)
        .defaultSize(width: 560, height: 460)
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/Merkzettel/Merkzettel.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "Merkzettel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "Merkzettel.store")
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Project.self, Entry.self, configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}

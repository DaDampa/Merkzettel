import ServiceManagement
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .obsidian: ObsidianSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, obsidian, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Allgemein"
        case .obsidian: "Obsidian"
        case .appearance: "Darstellung"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .obsidian: "books.vertical"
        case .appearance: "paintpalette"
        }
    }
}

/// The link to an Obsidian vault: one Markdown note per project.
struct ObsidianSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("obsidian.enabled") private var enabled = false
    @AppStorage("obsidian.vault") private var vault = ""
    @AppStorage("obsidian.folder") private var folder = "Merkzettel"
    @AppStorage("obsidian.archive") private var archive = true
    private let known = AppModel.knownVaults

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Auswählen"
        panel.message = "Wähle den Ordner deines Obsidian-Vaults."
        if panel.runModal() == .OK, let url = panel.url { vault = url.path }
    }

    var body: some View {
        Section {
            Toggle("Projekte in Obsidian ablegen", isOn: $enabled)
            Picker("Vault", selection: $vault) {
                if vault.isEmpty { Text("Nicht gewählt").tag("") }
                ForEach(known, id: \.self) { Text(($0 as NSString).lastPathComponent).tag($0) }
                if !vault.isEmpty, !known.contains(vault) { Text((vault as NSString).lastPathComponent).tag(vault) }
            }
            .help(vault)
            LabeledContent("Anderer Ordner") {
                Button("Wählen …") { chooseVault() }
            }
            TextField("Ordner im Vault", text: $folder, prompt: Text("Merkzettel"))
            Toggle("Archiv mit aufnehmen", isOn: $archive)
        } header: {
            Text("Verknüpfung")
        } footer: {
            Text("Jedes Projekt wird eine Notiz im gewählten Ordner des Vaults: offene Aufgaben als Kästchen mit Termin, Notizen darunter, Bilder in „Anhänge“. Die Notizen schreibt Merkzettel; was du in Obsidian daran änderst, wird überschrieben.")
        }
        Section {
            LabeledContent("Stand") {
                Text(model.obsidianStatus.isEmpty ? (enabled && !vault.isEmpty ? "Noch nicht geschrieben" : "Verknüpfung ist aus") : model.obsidianStatus)
                    .foregroundStyle(model.obsidianFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            LabeledContent("Alle Projekte") {
                Button("Jetzt schreiben") { model.writeObsidian() }
                    .disabled(!enabled || vault.isEmpty)
            }
        }
        .onChange(of: enabled) { model.writeObsidian() }
        .onChange(of: vault) { model.writeObsidian() }
        .onChange(of: archive) { model.writeObsidian() }
        .onSubmit { model.writeObsidian() }
    }
}

struct GeneralSettings: View {
    @AppStorage("allSpaces") private var allSpaces = false
    @AppStorage("projectRoot") private var projectRoot = ""
    @AppStorage("archiveFile") private var archiveFile = true

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Auswählen"
        panel.message = "In diesem Ordner legt Merkzettel für jedes neue Projekt einen Unterordner an."
        if panel.runModal() == .OK, let url = panel.url { projectRoot = url.path }
    }
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Section {
            LabeledContent("Ordner für neue Projekte") {
                Text(projectRoot.isEmpty ? "Nicht festgelegt" : (projectRoot as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(projectRoot)
                Button("Wählen …") { chooseRoot() }
                if !projectRoot.isEmpty {
                    Button("Entfernen") { projectRoot = "" }
                }
            }
            Toggle("Archiv als Datei im Projektordner ablegen", isOn: $archiveFile)
        } header: {
            Text("Projektordner")
        } footer: {
            Text("Jedes neue Projekt bekommt in diesem Ordner einen Unterordner mit seinem Namen. Das Archiv liegt dort als „Merkzettel-Archiv.md“, Bilder daneben in „Merkzettel-Bilder“.")
        }
        Section {
            Toggle("Auf allen Schreibtischen zeigen", isOn: $allSpaces)
        } header: {
            Text("Fenster")
        } footer: {
            Text("Mit der Stecknadel in der Symbolleiste bleibt das Fenster im Vordergrund. Diese Option zeigt es zusätzlich auf jedem Schreibtisch.")
        }
        Section("Start") {
            Toggle("Beim Anmelden starten", isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))
        }
    }
}

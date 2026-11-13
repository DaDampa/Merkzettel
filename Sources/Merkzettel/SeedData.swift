import Foundation
import SwiftData

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with realistic items (short and long titles, starred and not).
/// Replace these with your app's own types. Seed only what a person can
/// create in the app, or the snapshots show features no one can use.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Project>())) ?? 0) == 0 else { return }
        let catalog = model.addProject(name: "Katalog-Import", folder: URL(fileURLWithPath: "/tmp/Katalog-Import"))
        model.add("Artikelstamm mit Lieferant abgleichen\nPreisliste 2027 importieren\nTestlauf mit 500 Artikeln\nAbnahmetermin mit Einkauf abstimmen\nKonzept freigeben", kind: .todo, to: catalog)
        let todos = catalog.entries(.todo)
        model.add("EAN-Dubletten: Lieferant schickt bis Freitag eine bereinigte Datei.", kind: .note, to: catalog, under: todos[0])
        model.add("Ansprechpartner: Herr Brandt, Stammdaten.", kind: .note, to: catalog, under: todos[0])
        model.add("Import läuft nachts um 2 Uhr, Protokoll geht per Mail an die IT.", kind: .note, to: catalog, under: todos[1])
        model.add("Terminvorschlag vom Einkauf: KW 48.", kind: .note, to: catalog, under: todos[3])
        model.add("Freigabe durch Projektleitung am 3.11.", kind: .note, to: catalog, under: todos[4])
        model.addImage(ImageTools.sample(), to: catalog, under: todos[1])?.text = "Bildschirmfoto der Importmaske"
        model.archive(todos[4])
        if let note = todos[3].openNotes.first { model.archive(note) }

        let day: TimeInterval = 86_400
        model.setDue(todos[0], Date.now.addingTimeInterval(-2 * day))
        model.setDue(todos[1], .now)
        model.setDue(todos[3], Date.now.addingTimeInterval(4 * day))
        let shop = model.addProject(name: "Webshop Relaunch")
        model.add("Angebot der Agentur prüfen\nLastenheft ergänzen", kind: .todo, to: shop)
        if let offer = shop.entries(.todo).first { model.setDue(offer, Date.now.addingTimeInterval(3 * day)) }
        if let spec = shop.entries(.todo).last { model.setDue(spec, Date.now.addingTimeInterval(30 * day)) }
        let lager = model.addProject(name: "Lagerumzug")
        model.add("Spedition anfragen", kind: .todo, to: lager)
        model.showsAgenda = false
        model.projectID = catalog.id
        model.renamingID = nil
    }
}

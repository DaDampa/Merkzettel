# Merkzettel

Kompakte macOS-App für Projektmanager: Projekte links, Aufgaben als Überschriften mit Notizen und Bildern rechts, Termine über alle Projekte, Archiv, Fenster immer im Vordergrund.

![Projektseite](docs/shots/open-light.png)

## Funktionen

- **Projekte:** neu anlegen oder bestehende Finder-Ordner wählen. In den Einstellungen lässt sich ein Stammordner festlegen; jedes neue Projekt bekommt dort einen Unterordner.
- **Aufgaben:** jede Aufgabe ist eine Überschrift. Reihenfolge = Priorität, änderbar durch Ziehen am Griff rechts auf eine andere Aufgabe.
- **Notizen:** hängen unter ihrer Aufgabe, in der Liste höchstens drei Zeilen, per Symbol in einem eigenen großen Fenster zu öffnen.
- **Bilder:** als Notiz einfügen, mit Command-V in einer Notiz oder Notizzeile, per Knopf aus der Zwischenablage, als Datei oder per Ziehen auf die Aufgabe.
- **Termine:** Datumsfeld rechts neben der Aufgabe. Der Punkt „Termine" in der Seitenleiste zeigt alle datierten Aufgaben aller Projekte, gruppiert nach Überfällig, Heute, Nächste 7 Tage, Später. Ein Klick springt zur Aufgabe.
- **Wochenübersicht:** Über der Terminliste stehen die aktuelle und die nächste Woche (Montag bis Sonntag, mit Kalenderwoche). An jedem Tag zeigt eine Zahl, wie viele Aufgaben fällig sind; ein Klick auf den Tag zeigt nur diese.
- **Tastatur:** Umschalt-Return in einer Aufgabe springt in deren Notizzeile, Return bleibt bei den Aufgaben. Pfeil auf/ab wandert durch Aufgaben, Notizen und Eingabezeilen; ein offenes großes Notizfenster zeigt dabei immer die Notiz, in der der Cursor steht. Command-Return öffnet die aktive Notiz groß, in einer leeren Notizzeile legt es die Notiz dabei gleich an (bleibt sie leer, verschwindet sie beim Schließen wieder); im großen Notizfenster springen Wahl-Command-Pfeil links/rechts oder zwei kleine Pfeile zur vorigen und nächsten Notiz.
- **Archiv:** der Kreis vor der Aufgabe fragt nach und schiebt sie mit ihren Notizen ins Archiv. Einzelne Notizen lassen sich ebenfalls abschließen. Aus dem Archiv lässt sich alles zurückholen.
- **Archiv-Datei:** hat ein Projekt einen Ordner, schreibt die App das Archiv dort als `Merkzettel-Archiv.md`, Bilder daneben in `Merkzettel-Bilder`.
- **Obsidian:** In den Einstellungen lässt sich ein Obsidian-Vault verknüpfen. Jedes Projekt wird dort eine Markdown-Notiz mit offenen Aufgaben als Kästchen (Termin im Format des Tasks-Plugins), Notizen und Bildern. Erledigtes steht getrennt in einer Archiv-Notiz je Projekt; die Ordner für Projekte und Archiv sind frei wählbar. Änderungen gehen kurz nach dem Tippen automatisch nach Obsidian. Eine Notiz „Merkzettel-Index" verlinkt alle Projekte und hängt unter einer wählbaren übergeordneten Notiz, damit die Projekte in der Graph-Ansicht zusammenhängen. Die Richtung ist Merkzettel nach Obsidian.
- **Immer im Vordergrund:** Stecknadel in der Symbolleiste (Umschalt-Command-T), optional auf allen Schreibtischen.
- **Listen einfügen:** Umschalt-Command-V macht aus jeder Zeile der Zwischenablage eine Aufgabe.

## Voraussetzungen

macOS 26 oder neuer, Xcode 26 (Swift 6.2 oder neuer). Es gibt kein Xcode-Projekt, nur ein Swift-Paket.

## Bauen und starten

```bash
./build.sh --open
```

Das Skript baut, signiert (ad hoc, wenn kein Entwicklerzertifikat vorhanden ist) und installiert nach `~/Applications/Merkzettel.app`.

Prüfen:

```bash
swift test --scratch-path ~/Library/Developer/Merkzettel/test-build
tools/selftest.sh
tools/snap.sh
```

## Wo die Daten liegen

`~/Library/Application Support/Merkzettel/Merkzettel.store` (SwiftData). Projektordner enthalten nur die Archiv-Datei und deren Bilder.

## Aufbau

- `Sources/Merkzettel/` die App: `App.swift` (Fenster, Menüs), `Models.swift` (Datenmodell und alle Aktionen), `ContentView.swift` (Oberfläche), `SettingsView.swift`.
- `Sources/MerkzettelKit/` Logik ohne SwiftUI: Listen-Parser, Termin-Gruppen, Archiv-Dokument. Tests in `Tests/`.
- `CLAUDE.md` Regeln für das Arbeiten am Projekt mit Claude Code.

## Prompt zum Nachbauen mit Claude Code

Den folgenden Text in einer neuen Claude-Code-Sitzung in einem leeren Ordner einfügen:

```text
Baue mir eine native macOS-App „Merkzettel" in SwiftUI mit SwiftData, als Swift-Paket
ohne Xcode-Projekt, für macOS 26. Oberfläche auf Deutsch. Ein Build-Skript soll die App
bauen, ad hoc signieren und nach ~/Applications installieren.

Zweck: Ich bin Projektmanager und will pro Projekt kompakt Aufgaben und Notizen führen.

Fenster
- Kompaktes Fenster (Standard ca. 640 x 560, Minimum 440 x 320) mit Seitenleiste links
  und Inhalt rechts.
- Stecknadel in der Symbolleiste: Fenster bleibt immer im Vordergrund (Fensterebene
  „floating"), Zustand wird gemerkt. Einstellung: zusätzlich auf allen Schreibtischen zeigen.

Seitenleiste
- Oben der Punkt „Termine" mit Zähler für heute fällige und überfällige Aufgaben.
- Darunter die Projekte, per Ziehen sortierbar, mit Zähler der offenen Aufgaben.
- Unten ein Menü „+ Projekt": „Neues Projekt" (Name direkt in der Seitenleiste tippen)
  und „Bestehenden Ordner wählen …" (ein oder mehrere Finder-Ordner, Projekt heißt wie
  der Ordner). Rechtsklick: Umbenennen, Im Finder zeigen, Projekt löschen (mit Rückfrage,
  der Ordner bleibt).

Projektseite
- Jede Aufgabe ist eine fette Überschrift mit: Kreis links (erledigen), Datumsfeld rechts
  (Kalender-Symbol setzt heute, danach kompaktes Datumsfeld im Format TT.MM.JJJJ, rotes
  Ausrufezeichen wenn überfällig), Griff-Symbol ganz rechts.
- Unter der Aufgabe eingerückt ihre Notizen und ein Feld „Notiz hinzufügen"; Return fügt
  hinzu und lässt den Cursor im Feld. Der Block muss mit jeder Notiz mitwachsen: dafür
  ScrollView mit VStack verwenden, keine List (deren Zeilen wachsen beim Tippen nicht).
- Notizen zeigen in der Liste höchstens drei Zeilen. Ein Symbol öffnet die Notiz in einem
  eigenen, frei vergrößerbaren Fenster mit Texteditor.
- Bilder als Notiz: Knopf neben „Notiz hinzufügen" fügt das Bild aus der Zwischenablage
  ein, sonst Dateiauswahl; außerdem Bilddateien oder Bilder auf die Aufgabe ziehen.
  Command-V mit einem Bild in der Zwischenablage (und keinem Text) setzt es in die Notiz,
  in der der Cursor steht (der Text wird zur Bildunterschrift), in der Notizzeile oder
  Aufgabe als neue Bild-Notiz, im großen Notizfenster ebenso. Über den Tastatur-Monitor
  abfangen, weil ein Textfeld ein Bild sonst ignoriert.
  Bild mit Bildunterschrift anzeigen, Doppelklick öffnet es groß.
- Priorität: Aufgabe am Griff auf eine andere Aufgabe ziehen, sie nimmt deren Platz ein.
  Auf eine Aufgabe gezogener Text wird zur Notiz.
- Ganz unten „Neue Aufgabe". Mehrere Zeilen (z. B. per Befehl „Zeilen aus der
  Zwischenablage als Aufgaben einfügen", Umschalt-Command-V) werden zu mehreren Aufgaben;
  Aufzählungszeichen, Nummern und Kästchen am Zeilenanfang werden entfernt.
- Umschalter in der Symbolleiste: Offen | Archiv.

Erledigen und Archiv
- Klick auf den Kreis öffnet eine Rückfrage „Aufgabe erledigt?"; erst nach Bestätigung
  wandert die Aufgabe mit allen Notizen ins Archiv.
- Einzelne Notizen lassen sich über ein Archiv-Symbol abschließen.
- Das Archiv zeigt erledigte Aufgaben mit ihren Notizen und Datum, neueste zuerst;
  zurückholen, endgültig löschen, Archiv leeren (mit Rückfrage).

Termine
- Zeigt alle offenen Aufgaben mit Datum aus allen Projekten, gruppiert nach Überfällig,
  Heute, Nächste 7 Tage, Später, mit Projektname. Ein Klick springt zur Aufgabe im
  Projekt, scrollt hin und markiert sie kurz.

Wochenübersicht in „Termine"
- Über der Liste ein Raster mit der aktuellen und der nächsten Woche, Montag bis Sonntag,
  links die Kalenderwoche. Heute ist hervorgehoben. Ein Tag mit fälligen Aufgaben zeigt
  deren Anzahl als kleine Marke, bei vergangenen Tagen in Rot.
- Klick auf einen Tag zeigt in der Liste nur dessen Aufgaben; „Alle Termine zeigen" hebt
  das wieder auf.

Tastatur
- Im Feld „Neue Aufgabe": Return legt die Aufgabe an und bleibt im Feld. Umschalt-Return
  legt sie an und setzt den Cursor in „Notiz hinzufügen" dieser Aufgabe. In einer
  bestehenden Aufgabe oder Notiz springt Umschalt-Return in die Notizzeile der Aufgabe.
  Umschalt-Return über einen lokalen Tastatur-Monitor (NSEvent) abfangen, weil ein
  Textfeld es sonst wie Return behandelt.
- Pfeil auf/ab bewegt den Cursor zum Feld darüber oder darunter, in der Reihenfolge:
  Aufgabe, ihre Notizen, „Notiz hinzufügen", nächste Aufgabe, …, „Neue Aufgabe". In einem
  mehrzeiligen Text wandert der Cursor erst durch dessen Zeilen. Ebenfalls über den
  Tastatur-Monitor; schnelle Folgen zählen vom noch ausstehenden Ziel aus.
- Ein offenes großes Notizfenster folgt dem Cursor: Steht er in einer anderen Notiz,
  zeigt das Fenster diese, ohne die Tastatur zu übernehmen. Von mehreren Notizfenstern
  folgt nur das zuletzt benutzte.
- Command-Return (Menübefehl) öffnet die Notiz groß, in der der Cursor zuletzt stand. Steht der Cursor in der Zeile „Notiz hinzufügen“ (oder im Titel einer Aufgabe ohne Notiz), wird dort sofort eine Notiz angelegt – mit dem bereits getippten Text – und groß geöffnet; leer geschlossen wird sie wieder entfernt.
- Im großen Notizfenster ganz oben, sehr klein: zwei Pfeile „vorige" und „nächste" Notiz
  und „2 von 5". Wahl-Command-Pfeil links/rechts tun dasselbe. Reihenfolge: Aufgabe für
  Aufgabe in Prioritätsreihenfolge, die Notiz wechselt im selben Fenster.

Projektordner und Archiv-Datei
- Einstellung „Ordner für neue Projekte": Jedes neue Projekt bekommt dort einen
  Unterordner mit seinem Namen (/ und : durch - ersetzen; bei Namensgleichheit „Name 2").
- Hat ein Projekt einen Ordner, schreibt die App das Archiv bei jeder Änderung als
  „Merkzettel-Archiv.md" dorthin (Aufgabe als Überschrift mit Erledigt-Datum und Termin,
  Notizen als Liste), Bilder nach „Merkzettel-Bilder". Abschaltbar in den Einstellungen.

Obsidian
- Eigener Einstellungs-Reiter „Obsidian": Schalter „Projekte in Obsidian ablegen", Auswahl
  des Vaults (bekannte Vaults aus ~/Library/Application Support/obsidian/obsidian.json,
  sonst Ordner wählen), „Projektordner" (Standard „Merkzettel"), Schalter „Archiv in
  Obsidian ablegen", „Archivordner" (Standard „Merkzettel/Archiv"); beide Ordner
  als Textfeld plus Ordnerauswahl innerhalb des Vaults. Anzeige des letzten
  Schreibzeitpunkts oder Fehlers, Knopf „Jetzt schreiben".
- Je Projekt eine Projektnotiz: Frontmatter mit den Tags „merkzettel" und dem Projektnamen
  als Tag (nur Buchstaben, Ziffern, _ und -, also „Kunde Nord" wird „Kunde-Nord"; die
  Archiv-Notiz trägt „merkzettel-archiv" und denselben Projekt-Tag), Hinweis, dass die Notiz
  überschrieben wird, Link auf die Archiv-Notiz, offene Aufgaben als „- [ ]" in
  Prioritätsreihenfolge mit Termin als „📅 JJJJ-MM-TT", Notizen eingerückt darunter, Bilder
  als ![[Datei]] aus dem Unterordner „Anhänge".
- Erledigtes steht nicht in der Projektnotiz, sondern in einer eigenen Notiz
  „<Projekt> Archiv" im Archiv-Ordner: „- [x] … ✅ JJJJ-MM-TT" mit Notizen, dazu einzeln
  abgeschlossene Notizen, mit Link zurück zum Projekt.
- #Tags, die in Aufgaben oder Notizen getippt werden (z. B. „#TEST"), bleiben im Text
  stehen und kommen zusätzlich in die Tags der jeweiligen Projekt- oder Archiv-Notiz,
  jeder einmal, ohne reine Zahlen wie „#12".
- Zusätzlich eine Notiz „Merkzettel-Index" im Projektordner: ein Link je Projekt mit der
  Zahl offener Aufgaben, darüber „Übergeordnet: [[…]]" auf eine Notiz, die in den
  Einstellungen gewählt wird („Übergeordnete Notiz", beliebige Notiz des Vaults). Jede
  Projektnotiz verlinkt den Index, jede Archiv-Notiz ihr Projekt.
- Alle Links als Wikilink mit vollem Pfad ab dem Vault-Stamm und Kurzname ([[Pfad|Name]]),
  damit sie auch bei gleichnamigen Notizen eindeutig sind. Der Vault-Stamm ist der nächste
  Ordner ab dem gewählten aufwärts, der „.obsidian" enthält.
- Nur Richtung Merkzettel nach Obsidian. Etwa eine Sekunde nach jeder Änderung schreiben,
  auch nach jedem Tippen in Aufgaben und Notizen, und einmal beim Start. Dateien nur bei
  geändertem Inhalt anfassen. Umbenannte Projekte nehmen beide Notizen mit.
- „In Obsidian öffnen" im Rechtsklick-Menü des Projekts und als Menübefehl
  (obsidian://open?path=…).
- Ein Zahnrad unten in der Seitenleiste öffnet die Einstellungen.

Technik
- Datenmodell: Project (Name, Ordnerpfad, Reihenfolge) und Entry (Text, Art Aufgabe oder
  Notiz, archiviert, Archivdatum, Fälligkeitsdatum, Reihenfolge, Bild als externe Daten,
  Verweis auf die Aufgabe, zu der eine Notiz gehört; Löschen einer Aufgabe löscht ihre Notizen).
- Reine Logik (Listen-Parser, Termin-Gruppen, Markdown des Archivs, Ordnernamen) in ein
  eigenes Modul ohne SwiftUI mit Unit-Tests.
- Ein Selbsttest (--selftest) prüft die Aktionen auf einer Test-Datenbank in /tmp.
- Jede Aktion hat einen Menübefehl mit Tastenkürzel. Systemfarben und Systemschriften,
  hell und dunkel.

Baue, starte die App und prüfe sie, bevor du fertig meldest.
```

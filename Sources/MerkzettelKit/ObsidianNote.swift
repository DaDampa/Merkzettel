import Foundation

/// One project as a Markdown note for an Obsidian vault.
public enum ObsidianNote {
    public struct Note: Equatable, Sendable {
        public var text: String
        /// File name of the picture in the vault, embedded as ![[name]].
        public var imageFile: String?

        public init(text: String, imageFile: String? = nil) {
            self.text = text
            self.imageFile = imageFile
        }
    }

    public struct Task: Equatable, Sendable {
        public var title: String
        /// Due date as yyyy-MM-dd.
        public var due: String?
        /// For archived tasks: the day it was done, as yyyy-MM-dd.
        public var done: String?
        public var notes: [Note]

        public init(title: String, due: String? = nil, done: String? = nil, notes: [Note] = []) {
            self.title = title
            self.due = due
            self.done = done
            self.notes = notes
        }
    }

    /// A note that was finished on its own, while its task stays open.
    public struct FinishedNote: Equatable, Sendable {
        public var note: Note
        public var taskTitle: String?
        public var done: String

        public init(note: Note, taskTitle: String?, done: String) {
            self.note = note
            self.taskTitle = taskTitle
            self.done = done
        }
    }

    /// One project in the index note.
    public struct IndexItem: Equatable, Sendable {
        /// The finished link, from `link(_:alias:)`.
        public var link: String
        public var openTasks: Int

        public init(link: String, openTasks: Int) {
            self.link = link
            self.openTasks = openTasks
        }
    }

    /// A wikilink by full path inside the vault, shown under a short name. The
    /// path keeps the link exact when two notes in the vault share a name.
    public static func link(_ path: String, alias: String) -> String {
        path == alias ? "[[\(alias)]]" : "[[\(path)|\(oneLine(alias))]]"
    }

    /// The index note: one link per project, and a link up to the note it hangs
    /// below. In the graph it is the node that holds the projects together.
    public static func indexMarkdown(parentLink: String?, projects: [IndexItem]) -> String {
        var lines = header(tag: "merkzettel", project: nil)
        if let parentLink { lines += ["Übergeordnet: \(parentLink)", ""] }
        lines += ["## Projekte", ""]
        if projects.isEmpty { lines.append("Keine Projekte.") }
        for item in projects {
            let count = item.openTasks == 1 ? "1 offene Aufgabe" : "\(item.openTasks) offene Aufgaben"
            lines.append("- \(item.link) – \(count)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// The project note: open tasks as checkboxes in priority order, their notes
    /// indented below. The archive lives in a note of its own. `archiveNote` and
    /// `indexNote` are finished links from `link(_:alias:)`.
    /// Due and done dates use the emoji the Tasks plugin reads.
    public static func markdown(project: String, folder: String? = nil, open: [Task], loose: [Note] = [],
                                archiveNote: String? = nil, indexNote: String? = nil) -> String {
        let texts = open.flatMap { [$0.title] + $0.notes.map(\.text) } + loose.map(\.text)
        var lines = header(tag: "merkzettel", project: project, extra: hashtags(in: texts))
        if let indexNote { lines += ["Übersicht: \(indexNote)", ""] }
        if let folder, !folder.isEmpty {
            let link = "file://" + (folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folder)
            lines += ["Projektordner: [\(oneLine(folder))](\(link))", ""]
        }
        if let archiveNote { lines += ["Archiv: \(archiveNote)", ""] }
        lines += ["## Offene Aufgaben", ""]
        if open.isEmpty { lines.append("Keine offenen Aufgaben.") }
        for task in open { lines += block(task, box: "[ ]") }
        lines.append("")
        if !loose.isEmpty {
            lines += ["## Notizen ohne Aufgabe", ""]
            for note in loose { lines += bullet(note, indent: "") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// The archive note of a project: done tasks with their notes, then notes
    /// finished on their own. `projectNote` is the finished link back to the project.
    public static func archiveMarkdown(project: String, projectNote: String, archived: [Task], finished: [FinishedNote] = []) -> String {
        let texts = archived.flatMap { [$0.title] + $0.notes.map(\.text) } + finished.map(\.note.text)
        var lines = header(tag: "merkzettel-archiv", project: project, extra: hashtags(in: texts))
        lines += ["Projekt: \(projectNote)", "", "## Erledigte Aufgaben", ""]
        if archived.isEmpty { lines.append("Keine erledigten Aufgaben.") }
        for task in archived { lines += block(task, box: "[x]") }
        lines.append("")
        if !finished.isEmpty {
            lines += ["## Abgeschlossene Notizen", ""]
            for item in finished {
                let about = item.taskTitle.map { " zu „\(oneLine($0))“" } ?? ""
                lines.append("- Notiz\(about), abgeschlossen \(item.done)")
                lines += bullet(item.note, indent: "\t")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// A folder path inside the vault, every part made safe. Empty input gives the fallback.
    public static func folderPath(_ text: String, fallback: String) -> String {
        let parts = text.split(separator: "/").map { fileName(String($0)) }
        return parts.isEmpty ? fallback : parts.joined(separator: "/")
    }

    /// The project name as an Obsidian tag: letters, digits, "_" and "-" only,
    /// so "Kunde Nord" becomes "Kunde-Nord". A tag of digits alone is not allowed.
    public static func tag(_ name: String) -> String {
        let mapped = String(name.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "-" })
        let parts = mapped.split(separator: "-", omittingEmptySubsequences: true)
        let tag = parts.joined(separator: "-")
        if tag.isEmpty { return "projekt" }
        return tag.allSatisfy(\.isNumber) ? "projekt-\(tag)" : tag
    }

    /// The #tags typed into tasks and notes, in order of first use, each once
    /// (Obsidian ignores case in tags). "#12" is no tag, and neither is the
    /// "#" in "Nr.#5" or in a link like "seite#abschnitt".
    public static func hashtags(in texts: [String]) -> [String] {
        var seen: Set<String> = []
        var found: [String] = []
        func inTag(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "-" || character == "/"
        }
        for text in texts {
            let characters = Array(text)
            var index = 0
            while index < characters.count {
                defer { index += 1 }
                guard characters[index] == "#" else { continue }
                // A tag starts a word: no letter, digit, "_", "#" or "/" right before it.
                if index > 0, inTag(characters[index - 1]) && characters[index - 1] != "-" || index > 0 && characters[index - 1] == "#" { continue }
                var end = index + 1
                while end < characters.count, inTag(characters[end]) { end += 1 }
                let tag = String(characters[(index + 1)..<end]).trimmingCharacters(in: CharacterSet(charactersIn: "-/"))
                index = end - 1
                guard !tag.isEmpty, !tag.allSatisfy(\.isNumber), seen.insert(tag.lowercased()).inserted else { continue }
                found.append(tag)
            }
        }
        return found
    }

    private static func header(tag: String, project: String?, extra: [String] = []) -> [String] {
        let fixed = [tag] + (project.map { [Self.tag($0)] } ?? [])
        let known = Set(fixed.map { $0.lowercased() })
        let tags = fixed + extra.filter { !known.contains($0.lowercased()) }
        return ["---", "tags:"] + tags.map { "  - \($0)" } + ["quelle: Merkzettel", "---", "",
         "> [!info] Diese Notiz schreibt Merkzettel",
         "> Änderungen hier werden beim nächsten Speichern in Merkzettel überschrieben.", ""]
    }

    /// A file name Obsidian accepts and can link to: none of * " \ / < > : | ? # ^ [ ].
    public static func fileName(_ name: String) -> String {
        var cleaned = name.replacing(/[*"\\\/<>:|?#^\[\]]/, with: "-")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        return cleaned.isEmpty ? "Projekt" : cleaned
    }

    private static func block(_ task: Task, box: String) -> [String] {
        var head = "- \(box) \(oneLine(task.title))"
        if let due = task.due { head += " 📅 \(due)" }
        if let done = task.done { head += " ✅ \(done)" }
        return [head] + task.notes.flatMap { bullet($0, indent: "\t") }
    }

    private static func bullet(_ note: Note, indent: String) -> [String] {
        var text = note.text.split(whereSeparator: \.isNewline).map(String.init)
        if let file = note.imageFile {
            if text.isEmpty { text = ["![[\(file)]]"] } else { text.append("![[\(file)]]") }
        }
        guard let first = text.first else { return [] }
        return ["\(indent)- \(first)"] + text.dropFirst().map { "\(indent)  \($0)" }
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

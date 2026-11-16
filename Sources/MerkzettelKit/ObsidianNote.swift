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

    /// Open tasks as checkboxes in priority order, their notes indented below,
    /// then the archive. Due and done dates use the emoji the Tasks plugin reads.
    public static func markdown(project: String, folder: String? = nil, open: [Task], loose: [Note] = [],
                                archived: [Task] = [], finished: [FinishedNote] = [], includeArchive: Bool = true) -> String {
        var lines = ["---", "tags:", "  - merkzettel", "quelle: Merkzettel", "---", "",
                     "> [!info] Diese Notiz schreibt Merkzettel",
                     "> Änderungen hier werden beim nächsten Speichern in Merkzettel überschrieben.", ""]
        if let folder, !folder.isEmpty {
            let link = "file://" + (folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folder)
            lines += ["Projektordner: [\(oneLine(folder))](\(link))", ""]
        }
        lines += ["## Offene Aufgaben", ""]
        if open.isEmpty { lines.append("Keine offenen Aufgaben.") }
        for task in open { lines += block(task, box: "[ ]") }
        lines.append("")
        if !loose.isEmpty {
            lines += ["## Notizen ohne Aufgabe", ""]
            for note in loose { lines += bullet(note, indent: "") }
            lines.append("")
        }
        if includeArchive, !archived.isEmpty || !finished.isEmpty {
            lines += ["## Archiv", ""]
            for task in archived { lines += block(task, box: "[x]") }
            for item in finished {
                let about = item.taskTitle.map { " zu „\(oneLine($0))“" } ?? ""
                lines.append("- Notiz\(about), abgeschlossen \(item.done)")
                lines += bullet(item.note, indent: "\t")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
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

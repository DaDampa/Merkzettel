import Foundation

/// The archive of a project as a Markdown file for the project folder.
public enum ArchiveDocument {
    public struct Note: Equatable, Sendable {
        public var text: String
        /// Path of the picture relative to the archive file, if the note has one.
        public var imageFile: String?

        public init(text: String, imageFile: String? = nil) {
            self.text = text
            self.imageFile = imageFile
        }
    }

    public struct Item: Equatable, Sendable {
        public var title: String
        public var isTask: Bool
        /// When it was archived, already formatted.
        public var date: String
        /// The task's due date, already formatted.
        public var due: String?
        /// For a note archived on its own: the task it belongs to.
        public var taskTitle: String?
        public var imageFile: String?
        public var notes: [Note]

        public init(title: String, isTask: Bool, date: String, due: String? = nil, taskTitle: String? = nil, imageFile: String? = nil, notes: [Note] = []) {
            self.title = title
            self.isTask = isTask
            self.date = date
            self.due = due
            self.taskTitle = taskTitle
            self.imageFile = imageFile
            self.notes = notes
        }
    }

    public static let fileName = "Merkzettel-Archiv.md"
    public static let imageFolder = "Merkzettel-Bilder"

    public static func markdown(project: String, items: [Item]) -> String {
        var lines = ["# Archiv: \(oneLine(project))", "",
                     "Diese Datei schreibt Merkzettel. Änderungen hier werden beim nächsten Archivieren überschrieben.", ""]
        if items.isEmpty { lines += ["Das Archiv ist leer.", ""] }
        for item in items {
            if item.isTask {
                lines += ["## \(oneLine(item.title))", "", "Erledigt am \(item.date)" + (item.due.map { " · Termin \($0)" } ?? ""), ""]
                for note in item.notes { lines += bullet(note) }
                if !item.notes.isEmpty { lines.append("") }
            } else {
                let about = item.taskTitle.map { " zu „\(oneLine($0))“" } ?? ""
                lines += ["## Notiz\(about)", "", "Abgeschlossen am \(item.date)", ""]
                lines += bullet(Note(text: item.title, imageFile: item.imageFile))
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A folder name the Finder accepts: no slashes or colons, never empty, no leading dot.
    public static func folderName(_ name: String) -> String {
        var cleaned = name.replacing(/[\/:\\]/, with: "-")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        return cleaned.isEmpty ? "Projekt" : cleaned
    }

    private static func bullet(_ note: Note) -> [String] {
        var lines: [String] = []
        let text = note.text.split(whereSeparator: \.isNewline).map(String.init)
        if let first = text.first {
            lines.append("- \(first)")
            lines += text.dropFirst().map { "  \($0)" }
        }
        if let file = note.imageFile {
            let link = "![\(text.first ?? "Bild")](\(file.replacingOccurrences(of: " ", with: "%20")))"
            lines.append(text.isEmpty ? "- \(link)" : "  \(link)")
        }
        return lines
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

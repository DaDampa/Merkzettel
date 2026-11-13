import Foundation

/// Turns pasted or typed text into list entries. No SwiftUI here, so tests run without the app.
public enum ListParser {
    /// One entry per non-empty line, with bullets, numbers, and checkboxes removed.
    public static func items(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { strip(String($0)) }.filter { !$0.isEmpty }
    }

    /// "  - [ ] Angebot prüfen " becomes "Angebot prüfen".
    public static func strip(_ line: String) -> String {
        line.replacing(/^\s*(?:(?:[-*•–·]|\d+[.)])\s+|\[[ xX]?\]\s*)+/, with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// A project name never is empty.
    public static func projectName(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? "Neues Projekt" : words.joined(separator: " ")
    }
}

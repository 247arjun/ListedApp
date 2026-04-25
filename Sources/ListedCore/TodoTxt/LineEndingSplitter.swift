import Foundation

/// Detected line ending(s) inside a file.
public enum LineEnding: String, Sendable {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"
}

/// Splits raw file text into individual logical lines while preserving the original
/// line ending convention. Used by `TodoTxtFile`.
public struct LineEndingSplitter {
    public static func detect(in text: String) -> LineEnding {
        if text.contains("\r\n") { return .crlf }
        if text.contains("\r") { return .cr }
        return .lf
    }

    /// Splits without including line endings in the returned lines.
    /// Returns whether the original input ended with a trailing line ending.
    public static func split(_ text: String) -> (lines: [String], hasTrailingNewline: Bool, ending: LineEnding) {
        let ending = detect(in: text)
        guard !text.isEmpty else { return ([], false, ending) }
        let separator = ending.rawValue
        let parts = text.components(separatedBy: separator)
        // If the file ended with the separator, components(separatedBy:) yields a trailing "".
        if let last = parts.last, last.isEmpty {
            return (Array(parts.dropLast()), true, ending)
        }
        return (parts, false, ending)
    }

    public static func join(_ lines: [String], ending: LineEnding, trailingNewline: Bool) -> String {
        var result = lines.joined(separator: ending.rawValue)
        if trailingNewline {
            result.append(ending.rawValue)
        }
        return result
    }
}

import Foundation

/// One typed term from the search bar. Free text searches the description; tokens like
/// `+work`, `@phone`, `(A)`, `due:today`, `file:work.txt`, `is:done` are special.
public enum SearchTerm: Hashable, Sendable {
    case freeText(String)
    case project(String)
    case context(String)
    case priority(Character)
    case dueOn(LocalDate)
    case dueRelative(Relative)
    case file(String)
    case isCompleted(Bool)

    public enum Relative: String, Hashable, Sendable {
        case today
        case tomorrow
        case overdue
        case thisWeek
        case nextWeek
    }
}

/// Tokenises a free-form search string into typed `SearchTerm`s.
public struct SearchTokenizer: Sendable {
    public init() {}

    public func tokenize(_ raw: String) -> [SearchTerm] {
        let pieces = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var terms: [SearchTerm] = []
        var freeBuffer: [String] = []
        for piece in pieces {
            if let term = parseSpecial(piece) {
                if !freeBuffer.isEmpty {
                    terms.append(.freeText(freeBuffer.joined(separator: " ")))
                    freeBuffer.removeAll()
                }
                terms.append(term)
            } else {
                freeBuffer.append(piece)
            }
        }
        if !freeBuffer.isEmpty {
            terms.append(.freeText(freeBuffer.joined(separator: " ")))
        }
        return terms
    }

    private func parseSpecial(_ piece: String) -> SearchTerm? {
        if piece.count > 1, piece.hasPrefix("+") {
            return .project(String(piece.dropFirst()))
        }
        if piece.count > 1, piece.hasPrefix("@") {
            return .context(String(piece.dropFirst()))
        }
        if piece.count == 3, piece.hasPrefix("("), piece.hasSuffix(")"),
           let letter = piece.dropFirst().first, letter.isASCII, letter.isUppercase {
            return .priority(letter)
        }
        if piece.hasPrefix("due:") {
            let value = String(piece.dropFirst("due:".count))
            switch value.lowercased() {
            case "today": return .dueRelative(.today)
            case "tomorrow": return .dueRelative(.tomorrow)
            case "overdue": return .dueRelative(.overdue)
            case "this-week", "thisweek", "week": return .dueRelative(.thisWeek)
            case "next-week", "nextweek": return .dueRelative(.nextWeek)
            default:
                if let date = LocalDate.parse(value) { return .dueOn(date) }
                return nil
            }
        }
        if piece.hasPrefix("file:") {
            return .file(String(piece.dropFirst("file:".count)))
        }
        if piece == "is:done" || piece == "is:completed" { return .isCompleted(true) }
        if piece == "is:active" || piece == "is:open" { return .isCompleted(false) }
        return nil
    }
}

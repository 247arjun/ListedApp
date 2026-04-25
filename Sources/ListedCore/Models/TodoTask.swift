import Foundation

/// A non-fatal warning produced while parsing a todo.txt line.
public struct TodoParseWarning: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case malformedMetadata
        case invalidDate
        case suspiciousPriority
        case unknownToken
    }

    public var kind: Kind
    public var message: String
    public var token: String?

    public init(kind: Kind, message: String, token: String? = nil) {
        self.kind = kind
        self.message = message
        self.token = token
    }
}

/// Stable identity used by the runtime store. Distinct from the persisted `uid:` metadata,
/// because tasks may have no `uid` (e.g. lines authored in an external editor).
public struct TodoTaskID: Hashable, Codable, Sendable, CustomStringConvertible {
    public var rawValue: String
    public init(_ raw: String) { self.rawValue = raw }
    public init() { self.rawValue = UUID().uuidString }
    public var description: String { rawValue }
}

/// A single parsed todo.txt task.
///
/// `rawLine` always contains the original text. The other fields are derived
/// during parsing and are only authoritative when the task is mutated through
/// the structured editor; the serializer composes a new `rawLine` then.
///
/// Tasks are runtime-only state — the canonical persistence is the `.txt` file
/// itself. We deliberately don't conform to `Codable`.
public struct TodoTask: Identifiable, Hashable, Sendable {
    public var id: TodoTaskID
    public var sourceFileID: UUID
    public var lineNumber: Int

    /// Original line as authored. Includes any trailing whitespace within the line itself,
    /// but never the line terminator.
    public var rawLine: String

    public var isCompleted: Bool
    public var completionDate: LocalDate?
    public var priority: Character?
    /// `pri:X` value preserved while completed.
    public var preservedPriority: Character?
    public var creationDate: LocalDate?
    /// Description text without the structural prefix. Projects, contexts and metadata
    /// remain inline; we extract them for filtering but do not strip them from `description`.
    public var description: String
    public var projects: [String]
    public var contexts: [String]
    /// All `key:value` tokens, including `due`, `t`, `rec`, `uid`, `parent`, `pri`, etc.
    public var metadata: [String: String]
    public var uid: String?
    public var dueDate: LocalDate?
    public var thresholdDate: LocalDate?
    public var recurrence: String?
    public var parentUID: String?
    public var parseWarnings: [TodoParseWarning]

    public init(
        id: TodoTaskID = TodoTaskID(),
        sourceFileID: UUID,
        lineNumber: Int,
        rawLine: String,
        isCompleted: Bool = false,
        completionDate: LocalDate? = nil,
        priority: Character? = nil,
        preservedPriority: Character? = nil,
        creationDate: LocalDate? = nil,
        description: String = "",
        projects: [String] = [],
        contexts: [String] = [],
        metadata: [String: String] = [:],
        uid: String? = nil,
        dueDate: LocalDate? = nil,
        thresholdDate: LocalDate? = nil,
        recurrence: String? = nil,
        parentUID: String? = nil,
        parseWarnings: [TodoParseWarning] = []
    ) {
        self.id = id
        self.sourceFileID = sourceFileID
        self.lineNumber = lineNumber
        self.rawLine = rawLine
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.priority = priority
        self.preservedPriority = preservedPriority
        self.creationDate = creationDate
        self.description = description
        self.projects = projects
        self.contexts = contexts
        self.metadata = metadata
        self.uid = uid
        self.dueDate = dueDate
        self.thresholdDate = thresholdDate
        self.recurrence = recurrence
        self.parentUID = parentUID
        self.parseWarnings = parseWarnings
    }

    /// True for empty/whitespace-only lines that should be preserved as blank rows.
    public var isBlank: Bool {
        rawLine.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A "title-like" string with structural `key:value` tokens stripped (`due:`,
    /// `uid:`, `pri:` etc.). Projects (`+Foo`) and contexts (`@bar`) remain inline
    /// because some users want them in the headline; UIs that render projects /
    /// contexts as chips below should prefer `cleanTitle`.
    public var displayTitle: String {
        var working = description
        let stripKeys: Set<String> = ["due", "t", "rec", "uid", "parent", "pri", "order"]
        let parts = working.split(separator: " ", omittingEmptySubsequences: false)
        let kept = parts.filter { token in
            guard let colon = token.firstIndex(of: ":"), colon != token.startIndex else { return true }
            let key = String(token[..<colon])
            return !stripKeys.contains(key)
        }
        working = kept.joined(separator: " ")
        return working.trimmingCharacters(in: .whitespaces)
    }

    /// Title with **all** structural noise removed: `key:value` metadata, `+Project`
    /// tokens, and `@context` tokens. This is what list rows show by default — the
    /// chips beneath the row carry the project / context information.
    public var cleanTitle: String {
        let parts = description.split(separator: " ", omittingEmptySubsequences: true)
        let kept = parts.filter { token in
            // Drop +project tokens.
            if token.count > 1, token.first == "+" { return false }
            // Drop @context tokens.
            if token.count > 1, token.first == "@" { return false }
            // Drop key:value metadata tokens (but leave URLs like https://… alone —
            // the parser already protected them by not registering them as metadata,
            // so we mirror that protection here).
            if let colon = token.firstIndex(of: ":"), colon != token.startIndex {
                let key = String(token[..<colon])
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
                let isMetadataKey = !key.isEmpty && key.unicodeScalars.allSatisfy { allowed.contains($0) }
                let lowered = token.lowercased()
                let isURL = lowered.hasPrefix("http:") || lowered.hasPrefix("https:")
                    || lowered.hasPrefix("file:") || lowered.hasPrefix("mailto:")
                    || lowered.hasPrefix("tel:") || lowered.hasPrefix("ftp:")
                    || lowered.hasPrefix("ssh:") || lowered.hasPrefix("git:")
                if isMetadataKey && !isURL { return false }
            }
            return true
        }
        return kept.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

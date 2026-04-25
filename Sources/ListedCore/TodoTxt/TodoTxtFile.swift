import Foundation

/// In-memory representation of a parsed todo.txt file.
///
/// Each line of the file becomes a `TodoTask`, including blank lines. The container
/// remembers the line ending convention and trailing-newline state so the serializer
/// can write the file back without churn.
public struct TodoTxtFile: Sendable {
    public let id: UUID
    public var taskFileID: UUID
    public var tasks: [TodoTask]
    public var lineEnding: LineEnding
    public var hasTrailingNewline: Bool
    public var contentHash: String

    public init(
        id: UUID = UUID(),
        taskFileID: UUID,
        tasks: [TodoTask],
        lineEnding: LineEnding,
        hasTrailingNewline: Bool,
        contentHash: String
    ) {
        self.id = id
        self.taskFileID = taskFileID
        self.tasks = tasks
        self.lineEnding = lineEnding
        self.hasTrailingNewline = hasTrailingNewline
        self.contentHash = contentHash
    }

    // MARK: - Build / decode

    /// Parse `text` into a `TodoTxtFile` rooted in `taskFileID`.
    public static func parse(text: String, taskFileID: UUID, parser: TodoTxtParser = TodoTxtParser()) -> TodoTxtFile {
        let split = LineEndingSplitter.split(text)
        var tasks: [TodoTask] = []
        tasks.reserveCapacity(split.lines.count)
        for (index, line) in split.lines.enumerated() {
            let task = parser.parse(line: line, lineNumber: index + 1, sourceFileID: taskFileID)
            tasks.append(task)
        }
        return TodoTxtFile(
            taskFileID: taskFileID,
            tasks: tasks,
            lineEnding: split.ending,
            hasTrailingNewline: split.hasTrailingNewline,
            contentHash: SHA256Hash.hex(of: text)
        )
    }

    // MARK: - Serialize

    /// Re-render the entire file as one string. Untouched lines are emitted from their
    /// preserved `rawLine`; mutated lines (caller is responsible for re-serializing them
    /// into `rawLine`) are likewise emitted as-is.
    public func render() -> String {
        let lines = tasks.map { $0.rawLine }
        return LineEndingSplitter.join(lines, ending: lineEnding, trailingNewline: hasTrailingNewline)
    }

    /// Convenience: render and refresh `contentHash`.
    public mutating func renderAndHash() -> String {
        let text = render()
        contentHash = SHA256Hash.hex(of: text)
        return text
    }

    // MARK: - Lookup helpers

    public func task(withUID uid: String) -> TodoTask? {
        tasks.first(where: { $0.uid == uid })
    }

    public func index(of taskID: TodoTaskID) -> Int? {
        tasks.firstIndex(where: { $0.id == taskID })
    }
}

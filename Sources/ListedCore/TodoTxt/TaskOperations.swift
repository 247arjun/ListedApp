import Foundation

/// Pure functions that mutate a single `TodoTask`. None of these touch disk; the
/// repository is responsible for persisting changes.
public enum TaskOperations {

    // MARK: - Add

    /// Build a brand new task line.
    public static func make(
        description: String,
        priority: Character? = nil,
        creationDate: LocalDate? = nil,
        dueDate: LocalDate? = nil,
        thresholdDate: LocalDate? = nil,
        projects: [String] = [],
        contexts: [String] = [],
        sourceFileID: UUID,
        lineNumber: Int,
        addUID: Bool = true,
        addCreationDate: Bool = true,
        clock: () -> Date = Date.init
    ) -> TodoTask {
        let now = clock()
        let createDate = creationDate ?? (addCreationDate ? LocalDate.from(now) : nil)
        let uid = addUID ? ULID.generate(at: now) : nil

        // Compose description by appending project/context tokens that aren't already in the text.
        var descPieces = [description.trimmingCharacters(in: .whitespacesAndNewlines)]
        for p in projects where !descPieces[0].split(separator: " ").contains("+\(p)"[...]) {
            descPieces.append("+\(p)")
        }
        for c in contexts where !descPieces[0].split(separator: " ").contains("@\(c)"[...]) {
            descPieces.append("@\(c)")
        }
        let composedDescription = descPieces.filter { !$0.isEmpty }.joined(separator: " ")

        var task = TodoTask(
            sourceFileID: sourceFileID,
            lineNumber: lineNumber,
            rawLine: "",
            isCompleted: false,
            priority: priority,
            creationDate: createDate,
            description: composedDescription,
            projects: projects,
            contexts: contexts,
            dueDate: dueDate,
            thresholdDate: thresholdDate,
            parentUID: nil
        )
        if let uid {
            task.uid = uid
            task.metadata["uid"] = uid
        }
        if let dueDate { task.metadata["due"] = dueDate.iso8601 }
        if let thresholdDate { task.metadata["t"] = thresholdDate.iso8601 }

        let serialized = TodoTxtSerializer().serialize(task, mode: .rebuild)
        task.rawLine = serialized
        return task
    }

    // MARK: - Complete / reopen

    /// Mark `task` as completed, applying the spec rules:
    /// - prefix "x YYYY-MM-DD"
    /// - preserve creation date
    /// - move priority into `pri:X` metadata (if `preservePriority` enabled)
    public static func complete(
        _ task: TodoTask,
        on date: LocalDate = LocalDate.today(),
        preservePriority: Bool = true
    ) -> TodoTask {
        guard !task.isCompleted else { return task }
        var updated = task
        updated.isCompleted = true
        updated.completionDate = date
        if preservePriority, let p = task.priority {
            updated.preservedPriority = p
            updated.metadata["pri"] = String(p)
        }
        updated.priority = nil
        updated.rawLine = TodoTxtSerializer().serialize(updated, mode: .rebuild)
        return updated
    }

    /// Reverse the completion: drop the leading `x YYYY-MM-DD` and restore `pri:X` to the leading priority.
    public static func reopen(_ task: TodoTask) -> TodoTask {
        guard task.isCompleted else { return task }
        var updated = task
        updated.isCompleted = false
        updated.completionDate = nil
        if let p = task.preservedPriority {
            updated.priority = p
        }
        updated.preservedPriority = nil
        updated.metadata["pri"] = nil
        updated.rawLine = TodoTxtSerializer().serialize(updated, mode: .rebuild)
        return updated
    }

    // MARK: - Field edits

    public static func setDueDate(_ task: TodoTask, to date: LocalDate?) -> TodoTask {
        var updated = task
        updated.dueDate = date
        if let date {
            updated.metadata["due"] = date.iso8601
        } else {
            updated.metadata["due"] = nil
        }
        updated.rawLine = TodoTxtSerializer().serialize(updated, mode: .rebuild)
        return updated
    }

    public static func setThresholdDate(_ task: TodoTask, to date: LocalDate?) -> TodoTask {
        var updated = task
        updated.thresholdDate = date
        if let date {
            updated.metadata["t"] = date.iso8601
        } else {
            updated.metadata["t"] = nil
        }
        updated.rawLine = TodoTxtSerializer().serialize(updated, mode: .rebuild)
        return updated
    }

    public static func setPriority(_ task: TodoTask, to priority: Character?) -> TodoTask {
        var updated = task
        if task.isCompleted {
            updated.preservedPriority = priority
            if let priority {
                updated.metadata["pri"] = String(priority)
            } else {
                updated.metadata["pri"] = nil
            }
        } else {
            updated.priority = priority
        }
        updated.rawLine = TodoTxtSerializer().serialize(updated, mode: .rebuild)
        return updated
    }

    public static func setDescription(_ task: TodoTask, to newDescription: String) -> TodoTask {
        var updated = task
        updated.description = newDescription
        // Re-extract projects/contexts/metadata from the new description.
        let parser = TodoTxtParser()
        // Cheap re-parse of just the description portion.
        let pseudo = parser.parse(line: "RAW " + newDescription, lineNumber: task.lineNumber, sourceFileID: task.sourceFileID)
        updated.projects = pseudo.projects
        updated.contexts = pseudo.contexts
        // Merge: preserved typed metadata keys (due/t/uid/parent/pri) come from `task`; other keys from re-parse.
        var merged = task.metadata
        let managedKeys: Set<String> = ["due", "t", "rec", "uid", "parent", "pri"]
        for (k, v) in pseudo.metadata where !managedKeys.contains(k) {
            merged[k] = v
        }
        updated.metadata = merged
        updated.rawLine = TodoTxtSerializer().serialize(updated, mode: .rebuild)
        return updated
    }

    public static func addProject(_ task: TodoTask, _ project: String) -> TodoTask {
        guard !task.projects.contains(project) else { return task }
        var updated = task
        updated.projects.append(project)
        updated.description = appendingTokenIfMissing(updated.description, token: "+\(project)")
        updated.rawLine = TodoTxtSerializer().serialize(updated, mode: .rebuild)
        return updated
    }

    public static func removeProject(_ task: TodoTask, _ project: String) -> TodoTask {
        guard task.projects.contains(project) else { return task }
        var updated = task
        updated.projects.removeAll(where: { $0 == project })
        updated.description = removingToken(updated.description, token: "+\(project)")
        updated.rawLine = TodoTxtSerializer().serialize(updated, mode: .rebuild)
        return updated
    }

    public static func addContext(_ task: TodoTask, _ context: String) -> TodoTask {
        guard !task.contexts.contains(context) else { return task }
        var updated = task
        updated.contexts.append(context)
        updated.description = appendingTokenIfMissing(updated.description, token: "@\(context)")
        updated.rawLine = TodoTxtSerializer().serialize(updated, mode: .rebuild)
        return updated
    }

    public static func removeContext(_ task: TodoTask, _ context: String) -> TodoTask {
        guard task.contexts.contains(context) else { return task }
        var updated = task
        updated.contexts.removeAll(where: { $0 == context })
        updated.description = removingToken(updated.description, token: "@\(context)")
        updated.rawLine = TodoTxtSerializer().serialize(updated, mode: .rebuild)
        return updated
    }

    /// Replace the entire raw line (used by the raw-line editor). Re-parses the result.
    public static func replaceRawLine(_ task: TodoTask, newRawLine: String) -> TodoTask {
        let parser = TodoTxtParser()
        var reparsed = parser.parse(line: newRawLine, lineNumber: task.lineNumber, sourceFileID: task.sourceFileID)
        // Preserve the runtime ID so list selection survives the edit.
        reparsed.id = task.id
        return reparsed
    }

    // MARK: - String helpers

    private static func appendingTokenIfMissing(_ text: String, token: String) -> String {
        let pieces = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if pieces.contains(token) { return text }
        if text.isEmpty { return token }
        return text + " " + token
    }

    private static func removingToken(_ text: String, token: String) -> String {
        let pieces = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let kept = pieces.filter { $0 != token }
        return kept.joined(separator: " ")
    }
}

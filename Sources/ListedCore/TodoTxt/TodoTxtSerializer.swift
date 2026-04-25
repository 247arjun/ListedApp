import Foundation

/// Serializes a `TodoTask` back into a single todo.txt line.
///
/// Round-trip rule: if the structured fields haven't been edited, the parser+serializer
/// must produce a string equal to the original `rawLine`. The `serialize(_:mode:)` API
/// supports two modes:
///
/// - `.preserveRawIfPossible`: returns `task.rawLine` verbatim.
/// - `.rebuild`: regenerates the line from structured fields. Used after edits.
public struct TodoTxtSerializer: Sendable {

    public enum Mode: Sendable {
        case preserveRawIfPossible
        case rebuild
    }

    public init() {}

    public func serialize(_ task: TodoTask, mode: Mode = .rebuild) -> String {
        switch mode {
        case .preserveRawIfPossible:
            return task.rawLine
        case .rebuild:
            return rebuild(task)
        }
    }

    /// Builds a fresh todo.txt line from `task`'s structured fields.
    private func rebuild(_ task: TodoTask) -> String {
        // Only preserve a "blank" line when both the raw text and the structured
        // description are empty. A freshly minted task has an empty rawLine but a
        // non-empty description, and must be rebuilt.
        if task.isBlank && task.description.isEmpty { return task.rawLine }

        var prefix: [String] = []

        if task.isCompleted {
            prefix.append("x")
            if let comp = task.completionDate {
                prefix.append(comp.iso8601)
            }
            if let creation = task.creationDate {
                prefix.append(creation.iso8601)
            }
        } else {
            if let priority = task.priority {
                prefix.append("(\(priority))")
            }
            if let creation = task.creationDate {
                prefix.append(creation.iso8601)
            }
        }

        // Assemble the description by re-tokenizing the in-memory description and
        // rewriting/reapplying metadata in a stable order. Preserve the original
        // text where structured fields are unchanged.

        let originalTokens = task.description
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        // Remove well-known metadata tokens we will re-emit ourselves.
        let managedKeys: Set<String> = ["due", "t", "rec", "uid", "parent", "pri"]
        var bodyTokens: [String] = []
        for token in originalTokens {
            if let kv = parseKeyValue(token), managedKeys.contains(kv.key) {
                continue
            }
            bodyTokens.append(token)
        }

        // Append managed metadata in canonical order.
        var trailing: [String] = []
        if let due = task.dueDate { trailing.append("due:\(due.iso8601)") }
        if let t = task.thresholdDate { trailing.append("t:\(t.iso8601)") }
        if let rec = task.recurrence { trailing.append("rec:\(rec)") }
        if let parent = task.parentUID { trailing.append("parent:\(parent)") }
        if let uid = task.uid { trailing.append("uid:\(uid)") }
        if task.isCompleted, let pri = task.preservedPriority { trailing.append("pri:\(pri)") }

        var pieces = prefix + bodyTokens + trailing
        // Drop any empty tokens that may have leaked in.
        pieces.removeAll(where: { $0.isEmpty })
        return pieces.joined(separator: " ")
    }

    private func parseKeyValue(_ token: String) -> (key: String, value: String)? {
        guard let colon = token.firstIndex(of: ":") else { return nil }
        let key = String(token[..<colon])
        let valueStart = token.index(after: colon)
        guard valueStart < token.endIndex else { return nil }
        let value = String(token[valueStart...])
        if key.isEmpty || value.isEmpty { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        if key.unicodeScalars.contains(where: { !allowed.contains($0) }) { return nil }
        return (key, value)
    }
}

import Foundation

/// Parses a single todo.txt line into a `TodoTask`.
///
/// The parser is intentionally **non-mutating** with respect to the source text: every
/// task retains its `rawLine`, and the serializer prefers to round-trip that text
/// unchanged when no structured field has been edited.
public struct TodoTxtParser: Sendable {

    public init() {}

    /// Parse one line. `lineNumber` is 1-based.
    public func parse(line: String, lineNumber: Int, sourceFileID: UUID) -> TodoTask {
        var task = TodoTask(
            sourceFileID: sourceFileID,
            lineNumber: lineNumber,
            rawLine: line
        )

        let trimmed = line // we don't trim — preserve original

        // Blank line.
        if trimmed.trimmingCharacters(in: .whitespaces).isEmpty {
            task.description = ""
            return task
        }

        // Tokenize on spaces (single-space, multiple-space-collapsing happens in description reconstruction).
        var cursor = trimmed.startIndex

        // 1. Completion marker: lowercase "x " at line start.
        if let xRange = matchCompletionMarker(in: trimmed) {
            task.isCompleted = true
            cursor = xRange.upperBound

            // 2. Optional completion date.
            if let (date, range) = matchLeadingDate(in: trimmed, from: cursor) {
                task.completionDate = date
                cursor = range.upperBound
            }
        }

        // 3. Priority — only valid for active tasks (not for completed lines, where pri:X carries it).
        if !task.isCompleted, let (priority, range) = matchPriority(in: trimmed, from: cursor) {
            task.priority = priority
            cursor = range.upperBound
        }

        // 4. Creation date — appears after priority for active tasks, after completion date for completed.
        if let (date, range) = matchLeadingDate(in: trimmed, from: cursor) {
            task.creationDate = date
            cursor = range.upperBound
        }

        // 5. Remaining text becomes description (kept verbatim from this point).
        let remainingText = String(trimmed[cursor...])
        task.description = remainingText

        // 6. Project / context / metadata extraction over the remaining text only.
        extractTokens(from: remainingText, into: &task)

        // 7. Promote well-known metadata into typed fields.
        promoteMetadata(into: &task)

        return task
    }

    // MARK: - Sub-parsers

    /// Matches `"x "` at the start. Returns the range covering the `"x "` (including the trailing space).
    private func matchCompletionMarker(in s: String) -> Range<String.Index>? {
        // Must start with lowercase 'x' followed by a space.
        guard s.count >= 2 else { return nil }
        let i0 = s.startIndex
        let i1 = s.index(after: i0)
        if s[i0] == "x" && s[i1] == " " {
            return i0..<s.index(after: i1)
        }
        return nil
    }

    /// Matches a `(A)` priority at `from`. Returns the priority letter and the range
    /// that includes the trailing space (so the cursor advances past it).
    private func matchPriority(in s: String, from cursor: String.Index) -> (Character, Range<String.Index>)? {
        // Need at least 4 chars: "(A) "
        guard s.distance(from: cursor, to: s.endIndex) >= 4 else { return nil }
        let i0 = cursor
        let i1 = s.index(after: i0)
        let i2 = s.index(after: i1)
        let i3 = s.index(after: i2)
        guard s[i0] == "(", s[i2] == ")", s[i3] == " " else { return nil }
        let letter = s[i1]
        guard letter.isASCII, letter.isUppercase else { return nil }
        return (letter, i0..<s.index(after: i3))
    }

    /// Matches `YYYY-MM-DD ` at `from`. Returns the parsed date and the range covering the date plus trailing space.
    private func matchLeadingDate(in s: String, from cursor: String.Index) -> (LocalDate, Range<String.Index>)? {
        guard s.distance(from: cursor, to: s.endIndex) >= 11 else { return nil }
        let end = s.index(cursor, offsetBy: 10)
        let dateSlice = String(s[cursor..<end])
        guard let date = LocalDate.parse(dateSlice) else { return nil }
        let trailing = s.index(after: end)
        // Must be followed by space, OR end-of-string.
        if trailing == s.endIndex {
            return (date, cursor..<end)
        }
        if s[end] == " " {
            return (date, cursor..<trailing)
        }
        return nil
    }

    /// Walks the description, extracting `+project`, `@context` and `key:value` metadata.
    private func extractTokens(from text: String, into task: inout TodoTask) {
        let pieces = text.split(separator: " ", omittingEmptySubsequences: true)
        for piece in pieces {
            let token = String(piece)
            if token.count > 1, token.hasPrefix("+") {
                let name = String(token.dropFirst())
                if !name.isEmpty, !name.contains("+"), !name.contains("@") {
                    task.projects.append(name)
                    continue
                }
            }
            if token.count > 1, token.hasPrefix("@") {
                let name = String(token.dropFirst())
                if !name.isEmpty {
                    task.contexts.append(name)
                    continue
                }
            }
            if let kv = parseKeyValue(token) {
                // Heuristic: don't treat URL-ish tokens (http://, https://) as metadata.
                if isURLish(token) { continue }
                task.metadata[kv.key] = kv.value
            }
        }
        // Dedupe while preserving order
        task.projects = dedupe(task.projects)
        task.contexts = dedupe(task.contexts)
    }

    private func parseKeyValue(_ token: String) -> (key: String, value: String)? {
        guard let colon = token.firstIndex(of: ":") else { return nil }
        // Key must be non-empty and value must be non-empty.
        let key = String(token[..<colon])
        let valueStart = token.index(after: colon)
        guard valueStart < token.endIndex else { return nil }
        let value = String(token[valueStart...])
        if key.isEmpty || value.isEmpty { return nil }
        // Key must be alphanumeric / underscore / dash.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        if key.unicodeScalars.contains(where: { !allowed.contains($0) }) { return nil }
        return (key, value)
    }

    private func isURLish(_ token: String) -> Bool {
        let lower = token.lowercased()
        return lower.hasPrefix("http:") || lower.hasPrefix("https:") || lower.hasPrefix("file:") || lower.hasPrefix("mailto:") || lower.hasPrefix("tel:") || lower.hasPrefix("ftp:") || lower.hasPrefix("ssh:") || lower.hasPrefix("git:")
    }

    private func dedupe(_ array: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(array.count)
        for item in array where !seen.contains(item) {
            seen.insert(item)
            result.append(item)
        }
        return result
    }

    private func promoteMetadata(into task: inout TodoTask) {
        if let due = task.metadata["due"] {
            if let d = LocalDate.parse(due) {
                task.dueDate = d
            } else {
                task.parseWarnings.append(.init(kind: .invalidDate, message: "Invalid due date '\(due)'", token: "due:\(due)"))
            }
        }
        if let t = task.metadata["t"] {
            if let d = LocalDate.parse(t) {
                task.thresholdDate = d
            } else {
                task.parseWarnings.append(.init(kind: .invalidDate, message: "Invalid threshold date '\(t)'", token: "t:\(t)"))
            }
        }
        if let rec = task.metadata["rec"] {
            task.recurrence = rec
        }
        if let uid = task.metadata["uid"] {
            task.uid = uid
        }
        if let parent = task.metadata["parent"] {
            task.parentUID = parent
        }
        if let pri = task.metadata["pri"], let first = pri.first, pri.count == 1, first.isASCII, first.isUppercase {
            task.preservedPriority = first
        }
    }
}

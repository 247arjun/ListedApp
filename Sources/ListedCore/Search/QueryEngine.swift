import Foundation

/// Pure, in-memory query engine that turns a `TaskQuery` and a workspace snapshot
/// into the ordered list of tasks to display.
public struct QueryEngine: Sendable {
    public init() {}

    public func run(
        query: TaskQuery,
        files: [TodoTxtFile],
        taskFiles: [TaskFile],
        today: LocalDate = LocalDate.today()
    ) -> [TodoTask] {
        let taskFileByID = Dictionary(uniqueKeysWithValues: taskFiles.map { ($0.id, $0) })

        // 1. Pull the candidate tasks based on scope.
        var candidates: [TodoTask] = []
        switch query.scope {
        case .all, .smartList:
            for file in files {
                guard let tf = taskFileByID[file.taskFileID] else { continue }
                if tf.role == .reference { continue }
                candidates.append(contentsOf: file.tasks)
            }
        case .file(let id):
            if let file = files.first(where: { $0.taskFileID == id }) {
                candidates = file.tasks
            }
        case .project(let name):
            for file in files {
                candidates.append(contentsOf: file.tasks.filter { $0.projects.contains(name) })
            }
        case .context(let name):
            for file in files {
                candidates.append(contentsOf: file.tasks.filter { $0.contexts.contains(name) })
            }
        case .priority(let p):
            for file in files {
                candidates.append(contentsOf: file.tasks.filter { $0.priority == p })
            }
        }

        // 2. Drop blank lines from query results — they exist to preserve formatting,
        // not as user-visible tasks.
        candidates = candidates.filter { !$0.isBlank }

        // 3. Apply smart-list filter if any.
        if case .smartList(let kind) = query.scope {
            candidates = applySmartList(kind, to: candidates, today: today)
        }

        // 4. Active vs completed filter.
        if !query.includeCompleted, case .smartList(let kind) = query.scope, kind == .completed {
            // user explicitly wants completed; let it through
        } else if !query.includeCompleted, case .smartList(let kind) = query.scope, kind != .completed {
            candidates = candidates.filter { !$0.isCompleted }
        } else if !query.includeCompleted {
            candidates = candidates.filter { !$0.isCompleted }
        }

        // 5. Hide tasks past their threshold date.
        candidates = candidates.filter { task in
            guard let t = task.thresholdDate else { return true }
            return t <= today
        }

        // 6. Apply free-text search.
        if !query.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let terms = SearchTokenizer().tokenize(query.searchText)
            candidates = candidates.filter { matches(task: $0, terms: terms, today: today, taskFileByID: taskFileByID) }
        }

        // 7. Sort.
        return sort(candidates, configuration: query.sort, today: today)
    }

    // MARK: - Smart lists

    private func applySmartList(_ kind: TaskQuery.SmartList, to tasks: [TodoTask], today: LocalDate) -> [TodoTask] {
        switch kind {
        case .today:
            return tasks.filter { task in
                guard let due = task.dueDate, !task.isCompleted else { return false }
                return due <= today
            }
        case .upcoming:
            return tasks.filter { task in
                guard let due = task.dueDate, !task.isCompleted else { return false }
                return due > today
            }
        case .all:
            return tasks
        case .inbox:
            return tasks.filter { $0.projects.isEmpty && $0.contexts.isEmpty && !$0.isCompleted }
        case .completed:
            return tasks.filter { $0.isCompleted }
        }
    }

    // MARK: - Matching

    private func matches(task: TodoTask, terms: [SearchTerm], today: LocalDate, taskFileByID: [UUID: TaskFile]) -> Bool {
        for term in terms {
            switch term {
            case .freeText(let text):
                if !task.rawLine.localizedCaseInsensitiveContains(text) { return false }
            case .project(let name):
                if !task.projects.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) { return false }
            case .context(let name):
                if !task.contexts.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) { return false }
            case .priority(let letter):
                if task.priority != letter && task.preservedPriority != letter { return false }
            case .dueOn(let date):
                if task.dueDate != date { return false }
            case .dueRelative(let relative):
                if !matchesRelative(task: task, relative: relative, today: today) { return false }
            case .file(let name):
                guard let tf = taskFileByID[task.sourceFileID] else { return false }
                if tf.displayName.compare(name, options: .caseInsensitive) != .orderedSame &&
                   tf.relativePath.compare(name, options: .caseInsensitive) != .orderedSame {
                    return false
                }
            case .isCompleted(let flag):
                if task.isCompleted != flag { return false }
            }
        }
        return true
    }

    private func matchesRelative(task: TodoTask, relative: SearchTerm.Relative, today: LocalDate) -> Bool {
        guard let due = task.dueDate else { return false }
        switch relative {
        case .today: return due <= today
        case .tomorrow: return due == today.adding(days: 1)
        case .overdue: return due < today
        case .thisWeek:
            return due >= today && due <= today.adding(days: 7)
        case .nextWeek:
            return due > today.adding(days: 7) && due <= today.adding(days: 14)
        }
    }

    // MARK: - Sort

    public func sort(_ tasks: [TodoTask], configuration: SortConfiguration, today: LocalDate) -> [TodoTask] {
        let cmp = comparator(for: configuration.field, today: today)
        let sorted = tasks.sorted(by: cmp)
        return configuration.direction == .descending ? sorted.reversed() : sorted
    }

    private func comparator(for field: SortField, today: LocalDate) -> (TodoTask, TodoTask) -> Bool {
        switch field {
        case .smart:
            return { lhs, rhs in
                // overdue first, then today, then by priority, then by due, then manual order, then creation, then file/line.
                let lScore = smartScore(lhs, today: today)
                let rScore = smartScore(rhs, today: today)
                if lScore != rScore { return lScore < rScore }
                if (lhs.priority ?? "Z") != (rhs.priority ?? "Z") { return (lhs.priority ?? "Z") < (rhs.priority ?? "Z") }
                if let l = lhs.dueDate, let r = rhs.dueDate, l != r { return l < r }
                if lhs.dueDate != nil && rhs.dueDate == nil { return true }
                if lhs.dueDate == nil && rhs.dueDate != nil { return false }
                if let lo = manualOrder(lhs), let ro = manualOrder(rhs), lo != ro { return lo < ro }
                if let l = lhs.creationDate, let r = rhs.creationDate, l != r { return l < r }
                return lhs.lineNumber < rhs.lineNumber
            }
        case .manual:
            return { lhs, rhs in
                let lo = manualOrder(lhs) ?? Int.max
                let ro = manualOrder(rhs) ?? Int.max
                if lo != ro { return lo < ro }
                return lhs.lineNumber < rhs.lineNumber
            }
        case .fileOrder:
            return { $0.lineNumber < $1.lineNumber }
        case .dueDate:
            return { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case (nil, nil): return lhs.lineNumber < rhs.lineNumber
                case (nil, _): return false
                case (_, nil): return true
                case (let l?, let r?): return l < r
                }
            }
        case .priority:
            return { ($0.priority ?? "Z") < ($1.priority ?? "Z") }
        case .project:
            return { ($0.projects.first ?? "~") < ($1.projects.first ?? "~") }
        case .context:
            return { ($0.contexts.first ?? "~") < ($1.contexts.first ?? "~") }
        case .creationDate:
            return { lhs, rhs in
                switch (lhs.creationDate, rhs.creationDate) {
                case (nil, nil): return lhs.lineNumber < rhs.lineNumber
                case (nil, _): return false
                case (_, nil): return true
                case (let l?, let r?): return l < r
                }
            }
        case .sourceFile:
            return { $0.sourceFileID.uuidString < $1.sourceFileID.uuidString }
        }
    }

    private func smartScore(_ task: TodoTask, today: LocalDate) -> Int {
        if task.isCompleted { return 9 }
        guard let due = task.dueDate else { return 5 }
        if due < today { return 0 }      // overdue
        if due == today { return 1 }     // today
        let diff = today.daysBetween(due)
        if diff <= 7 { return 2 }        // this week
        return 3
    }

    private func manualOrder(_ task: TodoTask) -> Int? {
        guard let raw = task.metadata["order"] else { return nil }
        return Int(raw)
    }
}

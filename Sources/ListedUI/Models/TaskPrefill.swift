import Foundation
import ListedCore

/// Pre-filled values for `AddTaskSheet` so the user lands in a sheet where
/// the relevant fields (project, context, priority, due date) are already
/// populated to match the group they tapped "+" on.
public struct TaskPrefill: Hashable, Sendable {
    public var project: String?
    public var context: String?
    public var priority: Character?
    public var dueDate: LocalDate?

    public init(
        project: String? = nil,
        context: String? = nil,
        priority: Character? = nil,
        dueDate: LocalDate? = nil
    ) {
        self.project = project
        self.context = context
        self.priority = priority
        self.dueDate = dueDate
    }

    /// Empty prefill (everything `nil`) — used to detect "no prefill".
    public var isEmpty: Bool {
        project == nil && context == nil && priority == nil && dueDate == nil
    }
}

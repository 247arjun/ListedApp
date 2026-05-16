import Foundation

/// A bucket of tasks sharing a common attribute (priority, project, context,
/// due-date range, etc.). Produced by `QueryEngine.runGrouped(...)`.
public struct TaskGroup: Identifiable, Hashable, Sendable {
    /// Stable string identifier for this group. Used by views to track
    /// collapse state and animate group reorders across queries.
    /// Format: `"<field>:<value>"`, e.g. `"priority:A"`, `"project:home"`,
    /// `"due:thisWeek"`, `"none"`.
    public let id: String

    /// Human-readable title for the group header (e.g. "Priority A",
    /// "Home", "This Week", "No Project").
    public let title: String

    /// Optional sort key for ordering groups. `nil` groups are sorted
    /// to the end (for "None" / "Anytime" buckets).
    public let sortKey: String?

    /// Tasks in this group, in the order returned by the sort step
    /// (which runs before grouping).
    public let tasks: [TodoTask]

    public init(id: String, title: String, sortKey: String?, tasks: [TodoTask]) {
        self.id = id
        self.title = title
        self.sortKey = sortKey
        self.tasks = tasks
    }
}

/// Coarse buckets for the due-date grouping mode.
///
/// We deliberately use rolling-week semantics (not calendar weeks) so users
/// always see "the next 7 days" regardless of what day they look at the app:
/// - **This Week**: due today through today + 7 days
/// - **Next Week**: due 8–14 days from today
/// - **Later**: due more than 14 days out
/// - **Overdue**: due before today (active tasks only)
/// - **Anytime**: no due date set
public enum DueDateBucket: String, Hashable, Sendable, CaseIterable {
    case overdue
    case thisWeek
    case nextWeek
    case later
    case anytime

    /// Compute the bucket a task falls into based on its due date and today.
    public static func bucket(for date: LocalDate?, today: LocalDate = LocalDate.today()) -> DueDateBucket {
        guard let date else { return .anytime }
        if date < today { return .overdue }
        let daysAway = today.daysBetween(date)
        if daysAway <= 7 { return .thisWeek }
        if daysAway <= 14 { return .nextWeek }
        return .later
    }

    public var title: String {
        switch self {
        case .overdue:   return "Overdue"
        case .thisWeek:  return "This Week"
        case .nextWeek:  return "Next Week"
        case .later:     return "Later"
        case .anytime:   return "Anytime"
        }
    }

    /// Display order — overdue first, anytime last.
    public var displayOrder: Int {
        switch self {
        case .overdue:   return 0
        case .thisWeek:  return 1
        case .nextWeek:  return 2
        case .later:     return 3
        case .anytime:   return 4
        }
    }
}

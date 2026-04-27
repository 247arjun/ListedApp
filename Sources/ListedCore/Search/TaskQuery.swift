import Foundation

/// A high-level description of which tasks the UI wants to see.
public struct TaskQuery: Hashable, Sendable {
    public enum Scope: Hashable, Sendable {
        case all
        case smartList(SmartList)
        case file(UUID)
        case project(String)
        case context(String)
        case priority(Character)
    }

    public enum SmartList: String, Hashable, Sendable, CaseIterable, Codable {
        case today
        case upcoming
        case all
        case inbox
        case completed
    }

    public var scope: Scope
    public var searchText: String
    public var sort: SortConfiguration
    public var includeCompleted: Bool

    public init(scope: Scope, searchText: String = "", sort: SortConfiguration = .default, includeCompleted: Bool = false) {
        self.scope = scope
        self.searchText = searchText
        self.sort = sort
        self.includeCompleted = includeCompleted
    }
}

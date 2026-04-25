import Foundation

/// What this `.txt` file is used for in the app.
public enum TaskFileRole: String, Codable, Sendable, Hashable {
    case activeTodo
    case completedArchive
    case reference
}

/// A single `.txt` file containing tasks. Belongs to a `FileSource`.
public struct TaskFile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var sourceID: UUID
    public var displayName: String
    /// Path relative to the owning source's root. For `securityScopedFile` sources this
    /// is empty (the source itself is the file).
    public var relativePath: String
    public var role: TaskFileRole
    public var isEnabled: Bool
    public var sortOrder: Int
    public var lastKnownContentHash: String?
    public var lastLoadedAt: Date?

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        displayName: String,
        relativePath: String,
        role: TaskFileRole = .activeTodo,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        lastKnownContentHash: String? = nil,
        lastLoadedAt: Date? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.displayName = displayName
        self.relativePath = relativePath
        self.role = role
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.lastKnownContentHash = lastKnownContentHash
        self.lastLoadedAt = lastLoadedAt
    }
}

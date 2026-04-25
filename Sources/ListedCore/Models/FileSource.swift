import Foundation

/// What kind of storage location a `FileSource` represents.
public enum FileSourceKind: String, Codable, Sendable, Hashable {
    /// The app's iCloud ubiquity container (default storage).
    case appICloudContainer
    /// The app's local container (Documents directory).
    case appLocalContainer
    /// A user-selected folder accessed via security-scoped bookmark.
    case securityScopedFolder
    /// A user-selected single file accessed via security-scoped bookmark.
    case securityScopedFile
}

/// A user-approved storage location that can contain one or more `TaskFile`s.
public struct FileSource: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var displayName: String
    public var kind: FileSourceKind
    /// Bookmark for the root folder/file. Always `nil` for app-managed containers.
    public var rootBookmarkData: Data?
    /// Last resolved URL string (display purposes only — the bookmark is authoritative).
    public var rootURLString: String?
    public var isDefault: Bool
    public var isEnabled: Bool
    public var createdAt: Date
    public var lastAccessedAt: Date?

    public init(
        id: UUID = UUID(),
        displayName: String,
        kind: FileSourceKind,
        rootBookmarkData: Data? = nil,
        rootURLString: String? = nil,
        isDefault: Bool = false,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.rootBookmarkData = rootBookmarkData
        self.rootURLString = rootURLString
        self.isDefault = isDefault
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }

    /// True when access to this source requires `startAccessingSecurityScopedResource()`.
    public var requiresSecurityScope: Bool {
        switch kind {
        case .securityScopedFolder, .securityScopedFile: return true
        case .appICloudContainer, .appLocalContainer: return false
        }
    }
}

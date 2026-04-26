import Foundation

// MARK: - Sidebar configuration

public struct SidebarConfiguration: Codable, Hashable, Sendable {
    public var showSmartLists: Bool
    public var showFiles: Bool
    public var showProjects: Bool
    public var showContexts: Bool
    public var showPriorities: Bool
    public var showStorage: Bool

    public init(
        showSmartLists: Bool = true,
        showFiles: Bool = true,
        showProjects: Bool = true,
        showContexts: Bool = true,
        showPriorities: Bool = true,
        showStorage: Bool = true
    ) {
        self.showSmartLists = showSmartLists
        self.showFiles = showFiles
        self.showProjects = showProjects
        self.showContexts = showContexts
        self.showPriorities = showPriorities
        self.showStorage = showStorage
    }

    public static let `default` = SidebarConfiguration()
}

// MARK: - Sort

public enum SortField: String, Codable, Sendable, Hashable, CaseIterable {
    case smart        // overdue → today → priority → due → manual order → creation
    case manual       // order:<int> if present, else file/line order
    case fileOrder
    case dueDate
    case priority
    case project
    case context
    case creationDate
    case sourceFile
}

public enum SortDirection: String, Codable, Sendable, Hashable {
    case ascending
    case descending
}

public struct SortConfiguration: Codable, Hashable, Sendable {
    public var field: SortField
    public var direction: SortDirection
    public var grouping: GroupingField

    public init(field: SortField = .smart, direction: SortDirection = .ascending, grouping: GroupingField = .none) {
        self.field = field
        self.direction = direction
        self.grouping = grouping
    }

    public static let `default` = SortConfiguration()
}

public enum GroupingField: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    case file
    case project
    case context
    case dueDate
    case priority
    case completion
}

// MARK: - Saved filters

public struct SavedFilter: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var query: String

    public init(id: UUID = UUID(), name: String, query: String) {
        self.id = id
        self.name = name
        self.query = query
    }
}

// MARK: - Workspace

/// The user's saved app configuration. V1 ships with one workspace named "Default".
public struct Workspace: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var fileSources: [FileSource]
    public var taskFiles: [TaskFile]
    public var defaultTaskFileID: UUID?
    public var sidebarConfiguration: SidebarConfiguration
    public var sortConfiguration: SortConfiguration
    public var filterPresets: [SavedFilter]
    public var settings: AppSettings

    public init(
        id: UUID = UUID(),
        name: String = "Default",
        fileSources: [FileSource] = [],
        taskFiles: [TaskFile] = [],
        defaultTaskFileID: UUID? = nil,
        sidebarConfiguration: SidebarConfiguration = .default,
        sortConfiguration: SortConfiguration = .default,
        filterPresets: [SavedFilter] = [],
        settings: AppSettings = .default
    ) {
        self.id = id
        self.name = name
        self.fileSources = fileSources
        self.taskFiles = taskFiles
        self.defaultTaskFileID = defaultTaskFileID
        self.sidebarConfiguration = sidebarConfiguration
        self.sortConfiguration = sortConfiguration
        self.filterPresets = filterPresets
        self.settings = settings
    }
}

// MARK: - App settings

public enum DeleteMode: String, Codable, Sendable, Hashable, CaseIterable {
    case soft     // move to deleted.txt
    case hard     // remove the line
    case ask      // prompt every time (default)
}

/// How often Listed should auto-purge completed tasks from the active file.
/// Listed keeps everything in `todo.txt` (no `done.txt`); completed lines drift
/// to the bottom and get culled by this schedule.
public enum PurgeCadence: String, Codable, Sendable, Hashable, CaseIterable {
    /// Never auto-purge. The user can still tap "Delete completed tasks now".
    case never
    /// Daily — anything completed > 1 day ago is removed.
    case daily
    /// Weekly — anything completed > 7 days ago is removed.
    case weekly
    /// Monthly — anything completed > 30 days ago is removed.
    case monthly

    /// How many days of completed history to retain. `nil` means "no auto-purge".
    public var retentionDays: Int? {
        switch self {
        case .never: return nil
        case .daily: return 1
        case .weekly: return 7
        case .monthly: return 30
        }
    }

    /// Minimum gap between auto-purge runs. Avoids re-purging on every launch.
    public var minimumInterval: TimeInterval? {
        switch self {
        case .never: return nil
        case .daily: return 60 * 60 * 12        // run at most ~twice a day
        case .weekly: return 60 * 60 * 24       // run at most once a day
        case .monthly: return 60 * 60 * 24 * 3  // run at most every three days
        }
    }

    public var displayName: String {
        switch self {
        case .never: return "Never"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var addCreationDateToNewTasks: Bool
    public var addUIDToNewTasks: Bool
    public var preservePriorityOnCompletion: Bool
    public var groupCompletedAtBottom: Bool
    public var completedAutoPurge: PurgeCadence
    public var lastPurgeAt: Date?
    public var showCompletedInLists: Bool
    public var showRawMetadataInRows: Bool
    public var priorityRowHighlight: Bool
    public var menuBarEnabled: Bool
    public var deleteMode: DeleteMode

    public init(
        addCreationDateToNewTasks: Bool = true,
        addUIDToNewTasks: Bool = true,
        preservePriorityOnCompletion: Bool = true,
        groupCompletedAtBottom: Bool = true,
        completedAutoPurge: PurgeCadence = .never,
        lastPurgeAt: Date? = nil,
        showCompletedInLists: Bool = false,
        showRawMetadataInRows: Bool = false,
        priorityRowHighlight: Bool = true,
        menuBarEnabled: Bool = true,
        deleteMode: DeleteMode = .ask
    ) {
        self.addCreationDateToNewTasks = addCreationDateToNewTasks
        self.addUIDToNewTasks = addUIDToNewTasks
        self.preservePriorityOnCompletion = preservePriorityOnCompletion
        self.groupCompletedAtBottom = groupCompletedAtBottom
        self.completedAutoPurge = completedAutoPurge
        self.lastPurgeAt = lastPurgeAt
        self.showCompletedInLists = showCompletedInLists
        self.showRawMetadataInRows = showRawMetadataInRows
        self.priorityRowHighlight = priorityRowHighlight
        self.menuBarEnabled = menuBarEnabled
        self.deleteMode = deleteMode
    }

    public static let `default` = AppSettings()
}

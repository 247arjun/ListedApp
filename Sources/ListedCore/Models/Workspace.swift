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

public struct AppSettings: Codable, Hashable, Sendable {
    public var addCreationDateToNewTasks: Bool
    public var addUIDToNewTasks: Bool
    public var preservePriorityOnCompletion: Bool
    public var autoArchiveCompletedTasks: Bool
    public var showCompletedInLists: Bool
    public var showRawMetadataInRows: Bool
    public var priorityRowHighlight: Bool
    public var menuBarEnabled: Bool
    public var deleteMode: DeleteMode

    public init(
        addCreationDateToNewTasks: Bool = true,
        addUIDToNewTasks: Bool = true,
        preservePriorityOnCompletion: Bool = true,
        autoArchiveCompletedTasks: Bool = false,
        showCompletedInLists: Bool = false,
        showRawMetadataInRows: Bool = false,
        priorityRowHighlight: Bool = true,
        menuBarEnabled: Bool = true,
        deleteMode: DeleteMode = .ask
    ) {
        self.addCreationDateToNewTasks = addCreationDateToNewTasks
        self.addUIDToNewTasks = addUIDToNewTasks
        self.preservePriorityOnCompletion = preservePriorityOnCompletion
        self.autoArchiveCompletedTasks = autoArchiveCompletedTasks
        self.showCompletedInLists = showCompletedInLists
        self.showRawMetadataInRows = showRawMetadataInRows
        self.priorityRowHighlight = priorityRowHighlight
        self.menuBarEnabled = menuBarEnabled
        self.deleteMode = deleteMode
    }

    public static let `default` = AppSettings()
}

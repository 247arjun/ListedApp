import Foundation
import Observation
import ListedCore

/// The single source-of-truth view model used by every Listed UI surface.
///
/// `AppModel` owns the `TaskRepository` actor, exposes Observation-backed snapshots of
/// the workspace and tasks, and routes user actions back into the repository. It is
/// intentionally `@MainActor` so SwiftUI views can read its properties synchronously.
@MainActor
@Observable
public final class AppModel {

    // MARK: - Stored state

    public internal(set) var workspace: Workspace
    public internal(set) var loadedFiles: [TodoTxtFile] = []
    public internal(set) var lastError: AppError?
    public internal(set) var isBootstrapping: Bool = false

    /// Currently selected sidebar entry.
    public var selection: SidebarSelection = .smartList(.today)

    /// Free-form search bar text.
    public var searchText: String = ""

    /// Sort/group/order for the active query.
    public var sortConfiguration: SortConfiguration = .default

    /// Whether the user wants completed tasks to appear in non-Completed lists.
    public var showCompleted: Bool = false

    /// Currently selected task (drives the detail pane).
    public var selectedTaskID: TodoTaskID?

    // MARK: - Dependencies

    public let repository: TaskRepository
    public let workspaceStore: WorkspaceStore
    public let bootstrap: StorageBootstrap

    // MARK: - Init

    public init(workspace: Workspace,
                repository: TaskRepository,
                workspaceStore: WorkspaceStore = WorkspaceStore(),
                bootstrap: StorageBootstrap = StorageBootstrap()) {
        self.workspace = workspace
        self.repository = repository
        self.workspaceStore = workspaceStore
        self.bootstrap = bootstrap
    }

    /// Convenience factory used by the App entry point on launch.
    public static func makeForLaunch() async -> AppModel {
        let store = WorkspaceStore()
        let bootstrap = StorageBootstrap()
        var workspace: Workspace
        do {
            if let saved = try store.load() {
                workspace = saved
            } else {
                workspace = try bootstrap.makeInitialWorkspace(useICloud: bootstrap.isICloudAvailable)
                try store.save(workspace)
            }
        } catch {
            // Fall back to an in-memory empty workspace; the UI will surface an error.
            workspace = Workspace()
        }
        let repo = TaskRepository(workspace: workspace)
        let model = AppModel(workspace: workspace, repository: repo, workspaceStore: store, bootstrap: bootstrap)
        await model.refresh()
        return model
    }

    // MARK: - Lifecycle

    public func refresh() async {
        let errors = await repository.loadAllEnabled()
        let snapshot = await repository.loadedFiles()
        self.loadedFiles = snapshot
        if let first = errors.first {
            self.lastError = AppError(title: "Some files could not be loaded.", message: first.1.localizedDescription)
        }
    }

    public func startObservingChanges() {
        Task { [weak self] in
            guard let self else { return }
            let stream = await self.repository.events()
            for await _ in stream {
                let snapshot = await self.repository.loadedFiles()
                await MainActor.run {
                    self.loadedFiles = snapshot
                }
            }
        }
    }

    // MARK: - Derived state

    public var query: TaskQuery {
        TaskQuery(
            scope: selection.queryScope,
            searchText: searchText,
            sort: sortConfiguration,
            includeCompleted: showCompleted || selection == .smartList(.completed)
        )
    }

    public var visibleTasks: [TodoTask] {
        QueryEngine().run(
            query: query,
            files: loadedFiles,
            taskFiles: workspace.taskFiles
        )
    }

    public var defaultActiveFileID: UUID? {
        workspace.defaultTaskFileID ?? workspace.taskFiles.first(where: { $0.role == .activeTodo && $0.isEnabled })?.id
    }

    public func taskFile(forTaskFileID id: UUID) -> TaskFile? {
        workspace.taskFiles.first(where: { $0.id == id })
    }

    public func displayName(forTaskFileID id: UUID) -> String {
        taskFile(forTaskFileID: id)?.displayName ?? "Unknown"
    }

    public var selectedTask: TodoTask? {
        guard let id = selectedTaskID else { return nil }
        return loadedFiles.flatMap(\.tasks).first(where: { $0.id == id })
    }

    public var allProjects: [String] {
        let projects = loadedFiles.flatMap { $0.tasks.flatMap(\.projects) }
        return Array(Set(projects)).sorted()
    }

    public var allContexts: [String] {
        let contexts = loadedFiles.flatMap { $0.tasks.flatMap(\.contexts) }
        return Array(Set(contexts)).sorted()
    }

    public var usedPriorities: [Character] {
        let priorities = loadedFiles.flatMap { $0.tasks.compactMap { $0.priority ?? $0.preservedPriority } }
        return Array(Set(priorities)).sorted()
    }

    public var activeTaskFiles: [TaskFile] {
        workspace.taskFiles
            .filter { $0.isEnabled && $0.role != .reference }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public func taskCount(for selection: SidebarSelection) -> Int {
        let q = TaskQuery(scope: selection.queryScope, searchText: "", sort: .default, includeCompleted: selection == .smartList(.completed))
        return QueryEngine().run(query: q, files: loadedFiles, taskFiles: workspace.taskFiles).count
    }

    // MARK: - Mutations

    public func toggleCompletion(_ task: TodoTask) async {
        let updated: TodoTask
        if task.isCompleted {
            updated = TaskOperations.reopen(task)
        } else {
            updated = TaskOperations.complete(task, preservePriority: workspace.settings.preservePriorityOnCompletion)
        }
        await runMutation { try await self.repository.replace(task: updated) }
    }

    public func update(_ task: TodoTask) async {
        await runMutation { try await self.repository.replace(task: task) }
    }

    public func delete(_ task: TodoTask) async {
        await runMutation { try await self.repository.remove(taskID: task.id, in: task.sourceFileID) }
    }

    public func addTask(description: String, in fileID: UUID, priority: Character? = nil, dueDate: LocalDate? = nil) async {
        let task = TaskOperations.make(
            description: description,
            priority: priority,
            dueDate: dueDate,
            sourceFileID: fileID,
            lineNumber: 0,
            addUID: workspace.settings.addUIDToNewTasks,
            addCreationDate: workspace.settings.addCreationDateToNewTasks
        )
        await runMutation {
            _ = try await self.repository.appendTask(task, to: fileID)
        }
    }

    public func archiveCompleted(in fileID: UUID, into archiveID: UUID) async {
        await runMutation {
            _ = try await self.repository.archiveCompleted(from: fileID, to: archiveID)
        }
    }

    public func moveTask(_ task: TodoTask, to destinationID: UUID) async {
        await runMutation {
            try await self.repository.moveTask(task, toFileID: destinationID)
        }
    }

    /// Reorder a contiguous bucket of tasks inside one file. The repository will
    /// rewrite the file's line order so the listed task IDs occupy their slots in
    /// the order given. Used by drag-and-drop within the same file + same priority.
    public func reorderBucket(in fileID: UUID, taskIDs: [TodoTaskID]) async {
        await runMutation {
            try await self.repository.reorderTasksInFile(fileID, taskIDs: taskIDs)
        }
    }

    public func dismissError() {
        lastError = nil
    }

    private func runMutation(_ work: @escaping () async throws -> Void) async {
        do {
            try await work()
            self.loadedFiles = await repository.loadedFiles()
        } catch {
            self.lastError = AppError(title: "Couldn't save", message: error.localizedDescription)
        }
    }

    // MARK: - File source management

    public func addExternalFile(_ url: URL) async {
        do {
            let updated = try bootstrap.addExternalFile(url, to: workspace)
            try workspaceStore.save(updated)
            self.workspace = updated
            await repository.updateWorkspace(updated)
            await refresh()
        } catch {
            lastError = AppError(title: "Couldn't add file", message: error.localizedDescription)
        }
    }

    public func addExternalFolder(_ url: URL) async {
        do {
            let updated = try bootstrap.addExternalFolder(url, to: workspace)
            try workspaceStore.save(updated)
            self.workspace = updated
            await repository.updateWorkspace(updated)
            await refresh()
        } catch {
            lastError = AppError(title: "Couldn't add folder", message: error.localizedDescription)
        }
    }

    public func setDefaultFile(_ id: UUID) async {
        var updated = workspace
        updated.defaultTaskFileID = id
        do {
            try workspaceStore.save(updated)
            self.workspace = updated
            await repository.updateWorkspace(updated)
        } catch {
            lastError = AppError(title: "Couldn't update settings", message: error.localizedDescription)
        }
    }
}

/// A user-facing error surfaced through the app.
public struct AppError: Hashable, Sendable {
    public var title: String
    public var message: String
    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

/// Identifier for the current sidebar selection.
public enum SidebarSelection: Hashable, Sendable {
    case smartList(TaskQuery.SmartList)
    case file(UUID)
    case project(String)
    case context(String)
    case priority(Character)

    public var queryScope: TaskQuery.Scope {
        switch self {
        case .smartList(let s): return .smartList(s)
        case .file(let id): return .file(id)
        case .project(let p): return .project(p)
        case .context(let c): return .context(c)
        case .priority(let p): return .priority(p)
        }
    }
}

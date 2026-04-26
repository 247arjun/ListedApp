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
    /// True while a background read of the real (non-cached) files is in flight.
    /// Drives the small "Updating…" indicator in the toolbar — never blocks UI.
    public internal(set) var isRefreshing: Bool = false

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
    public let cache: TaskCacheStore

    // MARK: - Init

    public init(workspace: Workspace,
                repository: TaskRepository,
                workspaceStore: WorkspaceStore = WorkspaceStore(),
                bootstrap: StorageBootstrap = StorageBootstrap(),
                cache: TaskCacheStore = TaskCacheStore()) {
        self.workspace = workspace
        self.repository = repository
        self.workspaceStore = workspaceStore
        self.bootstrap = bootstrap
        self.cache = cache
    }

    // MARK: - Synchronous launch path

    /// Build the model **without ever touching iCloud**. Reads the saved workspace
    /// JSON and the per-file disk cache, both of which live in Application Support
    /// and resolve in microseconds. The result is a model whose `loadedFiles` is
    /// already populated with the user's last-known tasks, ready to render in the
    /// first frame.
    ///
    /// Call `startBackgroundRefresh()` afterwards to kick off the real iCloud /
    /// external-file read on a background `Task`.
    @MainActor
    public static func makeForLaunchSynchronously() -> AppModel {
        let resolver = FileURLResolver()
        let store = WorkspaceStore(resolver: resolver)
        let bootstrap = StorageBootstrap(resolver: resolver)
        let cache = TaskCacheStore(resolver: resolver)

        var workspace: Workspace
        do {
            if let saved = try store.load() {
                workspace = migrateSingleFileModel(saved)
                // Persist the migration so the next launch reads a clean workspace.
                if workspace != saved {
                    try? store.save(workspace)
                }
            } else {
                // No saved workspace — first launch. We deliberately do NOT call
                // `bootstrap.makeInitialWorkspace` here because it touches iCloud.
                // The onboarding sheet (driven by an empty fileSources list) will
                // take care of that explicitly.
                workspace = Workspace()
            }
        } catch {
            workspace = Workspace()
        }

        // Read each enabled file's cached text directly on the calling thread.
        // These are tiny synchronous file reads under Application Support — no
        // iCloud, no NSFileCoordinator, no actor hop. Then we parse and hand
        // the parsed files to the actor as a seed.
        let parser = TodoTxtParser()
        var primedFiles: [TodoTxtFile] = []
        for tf in workspace.taskFiles where tf.isEnabled {
            guard let text = cache.cachedText(for: tf.id) else { continue }
            var parsed = TodoTxtFile.parse(text: text, taskFileID: tf.id, parser: parser)
            parsed.contentHash = SHA256Hash.hex(of: text)
            primedFiles.append(parsed)
        }

        let repo = TaskRepository(workspace: workspace, resolver: resolver, cache: cache)
        let model = AppModel(
            workspace: workspace,
            repository: repo,
            workspaceStore: store,
            bootstrap: bootstrap,
            cache: cache
        )
        model.loadedFiles = primedFiles

        // Seed the actor with the same parsed files so subsequent reads/writes
        // see the cache-warmed state. Fire-and-forget; the main UI doesn't wait.
        Task.detached { await repo.seed(files: primedFiles) }

        return model
    }

    /// Back-compat factory that performs the full async refresh before returning.
    /// New code should prefer `makeForLaunchSynchronously()` plus a background
    /// `startBackgroundRefresh()`.
    public static func makeForLaunch() async -> AppModel {
        let model = await MainActor.run { makeForLaunchSynchronously() }
        await model.refresh()
        return model
    }

    // MARK: - Lifecycle

    /// Run the full read-from-source refresh on a background `Task`. Updates
    /// `loadedFiles` (and surfaces a banner error for the first failure, if any)
    /// when it completes. Safe to call repeatedly — the repository de-dupes via
    /// content hash.
    public func startBackgroundRefresh() {
        // If we have no enabled files yet (truly first launch), there's nothing
        // to fetch; the onboarding sheet will set things up and call refresh().
        guard !workspace.taskFiles.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            // After the refresh has populated loadedFiles, run the scheduled
            // completed-task purge if the cadence + cooldown call for it. The
            // purge is no-op for users on the default `.never` cadence.
            await self.runScheduledPurgeIfNeeded()
        }
    }

    public func refresh() async {
        // Pre-warm the iCloud container resolution off the launch path.
        Task.detached { [bootstrap] in
            bootstrap.resolver.prewarmICloud()
        }
        isRefreshing = true
        defer { isRefreshing = false }
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

    /// Priorities that have at least one **active** (non-completed) task. Drives
    /// the sidebar's Priorities section so it only lists priorities the user can
    /// currently click into and see results for. Completed tasks' preserved
    /// `pri:X` metadata is intentionally ignored here — those tasks are filtered
    /// out of the per-priority view by `QueryEngine` anyway.
    public var usedPriorities: [Character] {
        let priorities = loadedFiles.flatMap { file in
            file.tasks.compactMap { task -> Character? in
                guard !task.isCompleted, let p = task.priority else { return nil }
                return p
            }
        }
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

    /// Append a fully-prepared `TodoTask` to `fileID`. Used by the iOS new-task
    /// sheet, which builds the draft locally (with priority, due date, projects,
    /// contexts, threshold, raw line) and only commits when the user taps Add.
    public func appendPreparedTask(_ task: TodoTask, to fileID: UUID) async {
        var prepared = task
        prepared.sourceFileID = fileID
        await runMutation {
            _ = try await self.repository.appendTask(prepared, to: fileID)
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

    // MARK: - Purge completed

    /// Manual "Delete completed tasks now". Removes every completed task across
    /// all enabled active files, regardless of completion date. Updates
    /// `lastPurgeAt` on success so the auto-purge cooldown is reset.
    @discardableResult
    public func purgeCompletedTasksNow() async -> Int {
        return await runPurge(olderThan: nil)
    }

    /// Auto-purge entry point called from `startBackgroundRefresh()`. Honors
    /// `settings.completedAutoPurge` and `settings.lastPurgeAt`; no-op if the
    /// cadence is `.never` or the cooldown hasn't elapsed.
    public func runScheduledPurgeIfNeeded(now: Date = Date()) async {
        let cadence = workspace.settings.completedAutoPurge
        guard let retention = cadence.retentionDays,
              let interval = cadence.minimumInterval else { return }

        if let last = workspace.settings.lastPurgeAt,
           now.timeIntervalSince(last) < interval {
            return
        }
        let cutoff = LocalDate.today().adding(days: -retention)
        _ = await runPurge(olderThan: cutoff, now: now)
    }

    /// Shared purge worker. Returns the number of tasks removed.
    @discardableResult
    private func runPurge(olderThan cutoff: LocalDate?, now: Date = Date()) async -> Int {
        var removed = 0
        do {
            removed = try await repository.purgeCompletedTasks(olderThan: cutoff)
            self.loadedFiles = await repository.loadedFiles()
        } catch {
            self.lastError = AppError(title: "Couldn't purge completed tasks", message: error.localizedDescription)
            return 0
        }
        // Persist the purge timestamp regardless of how many were removed —
        // we still ran a check, and the cooldown is about "did we already try
        // recently," not "did we delete anything."
        var updated = workspace
        updated.settings.lastPurgeAt = now
        do {
            try workspaceStore.save(updated)
            self.workspace = updated
            await repository.updateWorkspace(updated)
        } catch {
            // Persistence failure shouldn't roll back the purge — the lines are
            // already gone on disk and that's user-visible. Surface a banner.
            self.lastError = AppError(title: "Couldn't save settings", message: error.localizedDescription)
        }
        return removed
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

/// One-time workspace migration applied at launch. Drops any `completedArchive`-role
/// task files left over from older Listed builds (back when there was a separate
/// `done.txt`). The on-disk `done.txt` is left alone — the user can still open it
/// later by re-importing it as an active file from Settings.
private func migrateSingleFileModel(_ workspace: Workspace) -> Workspace {
    var updated = workspace
    let archiveFiles = updated.taskFiles.filter { $0.role == .completedArchive }
    guard !archiveFiles.isEmpty else { return workspace }
    updated.taskFiles.removeAll { $0.role == .completedArchive }
    return updated
}

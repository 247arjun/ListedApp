import Foundation

/// What the repository observed when reloading a file.
public enum LoadOutcome: Sendable {
    case unchanged
    case loaded(TodoTxtFile)
}

/// The result of a write attempt that detected an external change.
public enum WriteConflictResolution: Sendable {
    /// Keep the user's intended changes and overwrite disk.
    case keepLocal
    /// Discard local changes and reload from disk.
    case keepDisk
}

/// Central read/write coordinator for all task files in a workspace.
///
/// `TaskRepository` is an actor so all file I/O is serialized per-instance. It keeps
/// in-memory `TodoTxtFile`s and notifies via an `AsyncStream` when content changes.
public actor TaskRepository {

    // MARK: - Dependencies

    private let resolver: FileURLResolver
    private let io: CoordinatedFileIO
    private let parser: TodoTxtParser
    private let serializer: TodoTxtSerializer
    /// Optional disk cache. When provided, every successful load/write also stamps
    /// the cache so the next launch can paint instantly without touching iCloud.
    private let cache: TaskCacheStore?

    // MARK: - State

    private var workspace: Workspace
    private var files: [UUID: TodoTxtFile] = [:]
    private var continuations: [UUID: AsyncStream<RepositoryEvent>.Continuation] = [:]

    // MARK: - Init

    public init(
        workspace: Workspace,
        resolver: FileURLResolver = FileURLResolver(),
        io: CoordinatedFileIO = CoordinatedFileIO(),
        parser: TodoTxtParser = TodoTxtParser(),
        serializer: TodoTxtSerializer = TodoTxtSerializer(),
        cache: TaskCacheStore? = nil
    ) {
        self.workspace = workspace
        self.resolver = resolver
        self.io = io
        self.parser = parser
        self.serializer = serializer
        self.cache = cache
    }

    // MARK: - Cache priming

    /// Synchronously preload all enabled files from the disposable cache, **without
    /// touching iCloud Drive or any security-scoped resource**. This is what powers
    /// the no-spinner launch path: call it from the launch task and the in-memory
    /// `loadedFiles()` will already be populated by the time the first frame paints.
    public func primeFromCache() {
        guard let cache else { return }
        for tf in enabledTaskFiles() {
            // Skip files we've already loaded this session.
            if files[tf.id] != nil { continue }
            guard let text = cache.cachedText(for: tf.id) else { continue }
            var parsed = TodoTxtFile.parse(text: text, taskFileID: tf.id, parser: parser)
            parsed.contentHash = SHA256Hash.hex(of: text)
            files[tf.id] = parsed
        }
    }

    /// Seed the actor's in-memory state with files that were already parsed by a
    /// caller (typically the synchronous launch path). Used to hand pre-rendered
    /// cache contents to the repository without performing any disk I/O ourselves.
    public func seed(files newFiles: [TodoTxtFile]) {
        for file in newFiles where files[file.taskFileID] == nil {
            files[file.taskFileID] = file
        }
    }

    // MARK: - Workspace access

    public func currentWorkspace() -> Workspace { workspace }

    public func updateWorkspace(_ updated: Workspace) {
        self.workspace = updated
        emit(.workspaceChanged)
    }

    // MARK: - Sources & files

    /// All enabled task files in the workspace, sorted by their stored sortOrder.
    public func enabledTaskFiles(role: TaskFileRole? = nil) -> [TaskFile] {
        workspace.taskFiles
            .filter { $0.isEnabled }
            .filter { role == nil || $0.role == role }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public func source(withID id: UUID) -> FileSource? {
        workspace.fileSources.first(where: { $0.id == id })
    }

    public func taskFile(withID id: UUID) -> TaskFile? {
        workspace.taskFiles.first(where: { $0.id == id })
    }

    public func file(forTaskFileID id: UUID) -> TodoTxtFile? {
        files[id]
    }

    /// Snapshot of all currently-loaded files.
    public func loadedFiles() -> [TodoTxtFile] {
        Array(files.values)
    }

    /// All tasks across loaded files.
    public func allTasks() -> [TodoTask] {
        files.values.flatMap { $0.tasks }
    }

    // MARK: - Loading

    /// Load (or reload) a single task file from disk.
    @discardableResult
    public func load(taskFileID: UUID) async throws -> LoadOutcome {
        guard let taskFile = taskFile(withID: taskFileID),
              let source = source(withID: taskFile.sourceID) else {
            throw StorageError.fileNotFound(URL(fileURLWithPath: "/dev/null"))
        }
        let resolved = try resolver.resolve(taskFile: taskFile, in: source)
        defer { resolved.release() }

        let url = resolved.url
        // On iOS especially, an iCloud Drive file may not be materialized yet.
        // Nudge the daemon to download it; we don't await — the read below will
        // block on coordination either way, but on subsequent launches the file
        // is more likely to already be local.
        #if os(iOS)
        if source.kind == .appICloudContainer {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        #endif

        if !io.fileExists(at: url) {
            // Treat a missing file as empty content.
            let empty = TodoTxtFile(taskFileID: taskFileID, tasks: [], lineEnding: .lf, hasTrailingNewline: true, contentHash: SHA256Hash.hex(of: ""))
            files[taskFileID] = empty
            updateLastLoaded(for: taskFileID, hash: empty.contentHash)
            cache?.write("", for: taskFileID)
            emit(.fileLoaded(taskFileID))
            return .loaded(empty)
        }

        let text = try io.readUTF8(at: url)
        let hash = SHA256Hash.hex(of: text)
        if let existing = files[taskFileID], existing.contentHash == hash {
            // Make sure the cache reflects what we just confirmed on disk, even
            // if our in-memory copy is unchanged. (No-op if cache already matches.)
            cache?.write(text, for: taskFileID)
            return .unchanged
        }
        var parsed = TodoTxtFile.parse(text: text, taskFileID: taskFileID, parser: parser)
        parsed.contentHash = hash
        files[taskFileID] = parsed
        updateLastLoaded(for: taskFileID, hash: hash)
        cache?.write(text, for: taskFileID)
        emit(.fileLoaded(taskFileID))
        return .loaded(parsed)
    }

    /// Load every enabled file in parallel.
    ///
    /// Each file load is independent — a slow iCloud download for `work.txt`
    /// must not gate the read of a fast local `personal.txt`. We fan out via a
    /// `TaskGroup` and only resolve the actor (this `TaskRepository`) inside
    /// each child task, so the actor itself isn't a serialization bottleneck.
    public func loadAllEnabled() async -> [(UUID, Error)] {
        let tasksToLoad = enabledTaskFiles()
        if tasksToLoad.isEmpty { return [] }

        return await withTaskGroup(of: (UUID, Error?).self) { group in
            for tf in tasksToLoad {
                group.addTask { [weak self] in
                    guard let self else { return (tf.id, nil) }
                    do {
                        try await self.load(taskFileID: tf.id)
                        return (tf.id, nil)
                    } catch {
                        return (tf.id, error)
                    }
                }
            }
            var errors: [(UUID, Error)] = []
            for await (id, error) in group {
                if let error { errors.append((id, error)) }
            }
            return errors
        }
    }

    // MARK: - Writing

    /// Apply `mutation` to the file's in-memory tasks, then write the file back to disk
    /// atomically. Detects external edits via content-hash comparison.
    ///
    /// If a conflict is detected, the closure is asked how to resolve it.
    public func mutate(
        taskFileID: UUID,
        resolveConflict: ((TodoTxtFile, TodoTxtFile) async -> WriteConflictResolution)? = nil,
        _ mutation: (inout TodoTxtFile) throws -> Void
    ) async throws {
        guard let taskFile = taskFile(withID: taskFileID),
              let source = source(withID: taskFile.sourceID) else {
            throw StorageError.fileNotFound(URL(fileURLWithPath: "/dev/null"))
        }
        let resolved = try resolver.resolve(taskFile: taskFile, in: source)
        defer { resolved.release() }
        let url = resolved.url

        // 1. Snapshot current in-memory file (or load it).
        if files[taskFileID] == nil {
            _ = try await load(taskFileID: taskFileID)
        }
        guard var working = files[taskFileID] else {
            throw StorageError.fileNotFound(url)
        }

        // 2. Re-read disk to see if it changed underneath us.
        let onDiskText: String
        if io.fileExists(at: url) {
            onDiskText = try io.readUTF8(at: url)
        } else {
            onDiskText = ""
        }
        let onDiskHash = SHA256Hash.hex(of: onDiskText)

        if onDiskHash != working.contentHash {
            // Conflict.
            let onDiskFile = TodoTxtFile.parse(text: onDiskText, taskFileID: taskFileID, parser: parser)
            let resolution: WriteConflictResolution
            if let resolveConflict {
                resolution = await resolveConflict(working, onDiskFile)
            } else {
                resolution = .keepDisk
            }
            switch resolution {
            case .keepDisk:
                files[taskFileID] = onDiskFile
                updateLastLoaded(for: taskFileID, hash: onDiskHash)
                emit(.fileLoaded(taskFileID))
                throw StorageError.writeConflict(url)
            case .keepLocal:
                // Re-base our working copy on disk content but keep in-memory tasks.
                working.contentHash = onDiskHash
            }
        }

        // 3. Apply mutation, render, and write.
        try mutation(&working)
        // Optionally re-partition so all completed tasks sit at the bottom of
        // the file. Stable: preserves existing order within each group, which
        // means manual drag-and-drop reorder + completion ordering compose
        // cleanly. Driven by the workspace setting; off → file untouched.
        if workspace.settings.groupCompletedAtBottom {
            partitionCompletedToBottom(&working)
        }
        let newText = working.renderAndHash()
        try io.writeUTF8(newText, to: url)
        files[taskFileID] = working
        updateLastLoaded(for: taskFileID, hash: working.contentHash)
        cache?.write(newText, for: taskFileID)
        emit(.fileSaved(taskFileID))
    }

    /// Stably re-orders tasks so all non-completed tasks come first (in their
    /// existing order), followed by all completed tasks (in their existing order).
    /// Blank-line "spacer" rows are kept where they sit relative to the active
    /// group so the file's section breaks remain readable in plain text.
    private func partitionCompletedToBottom(_ file: inout TodoTxtFile) {
        var active: [TodoTask] = []
        var completed: [TodoTask] = []
        active.reserveCapacity(file.tasks.count)
        for task in file.tasks {
            // Blank rows live with the active section so they continue to read
            // as visual spacers between active items rather than between
            // completed ones.
            if task.isCompleted {
                completed.append(task)
            } else {
                active.append(task)
            }
        }
        // No-op if order is already correct (avoids touching contentHash).
        if active.elementsEqual(file.tasks.prefix(active.count)) &&
           completed.elementsEqual(file.tasks.suffix(completed.count)) {
            return
        }
        var renumbered: [TodoTask] = []
        renumbered.reserveCapacity(active.count + completed.count)
        for (idx, task) in (active + completed).enumerated() {
            var t = task
            t.lineNumber = idx + 1
            renumbered.append(t)
        }
        file.tasks = renumbered
    }

    // MARK: - Purge

    /// Permanently delete every completed task whose `completionDate` is on or
    /// before `cutoff`. Tasks with no completion date are deleted unconditionally
    /// when `cutoff` is `nil` (used by the "Delete now" button) and skipped
    /// otherwise (we'd rather keep something undated than mis-delete it).
    ///
    /// Returns the total number of removed lines across all enabled active files.
    @discardableResult
    public func purgeCompletedTasks(olderThan cutoff: LocalDate?) async throws -> Int {
        var totalRemoved = 0
        for tf in enabledTaskFiles() where tf.role != .reference {
            let removed = try await purgeCompleted(in: tf.id, olderThan: cutoff)
            totalRemoved += removed
        }
        return totalRemoved
    }

    /// Purge inside a single file. Returns the number of lines removed.
    @discardableResult
    public func purgeCompleted(in taskFileID: UUID, olderThan cutoff: LocalDate?) async throws -> Int {
        var removed = 0
        try await mutate(taskFileID: taskFileID) { file in
            let before = file.tasks.count
            file.tasks.removeAll { task in
                guard task.isCompleted else { return false }
                guard let cutoff else { return true } // "Delete now" — drop everything completed
                guard let done = task.completionDate else { return false }
                return done <= cutoff
            }
            // Renumber whatever's left so subsequent edits don't think the
            // remaining tasks are at stale line positions.
            for i in file.tasks.indices {
                file.tasks[i].lineNumber = i + 1
            }
            removed = before - file.tasks.count
        }
        return removed
    }

    // MARK: - Add task

    /// Append a new task to `taskFileID`. Returns the inserted task with its final
    /// line number.
    @discardableResult
    public func appendTask(_ task: TodoTask, to taskFileID: UUID) async throws -> TodoTask {
        // Stamp the source-file ID up front so the closure's value capture is what we want.
        var stamped = task
        stamped.sourceFileID = taskFileID
        let snapshot = stamped
        var finalTask = stamped
        try await mutate(taskFileID: taskFileID) { file in
            var t = snapshot
            t.lineNumber = file.tasks.count + 1
            file.tasks.append(t)
            finalTask = t
        }
        return finalTask
    }

    // MARK: - Replace / update / remove

    public func replace(task: TodoTask) async throws {
        let fileID = task.sourceFileID
        try await mutate(taskFileID: fileID) { file in
            guard let idx = file.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            var updated = task
            updated.lineNumber = idx + 1
            file.tasks[idx] = updated
        }
    }

    public func remove(taskID: TodoTaskID, in taskFileID: UUID) async throws {
        try await mutate(taskFileID: taskFileID) { file in
            file.tasks.removeAll(where: { $0.id == taskID })
            // Renumber lineNumbers
            for i in file.tasks.indices {
                file.tasks[i].lineNumber = i + 1
            }
        }
    }

    /// Move a task between files (used by "move to another file" and archive flows).
    public func moveTask(_ task: TodoTask, toFileID destinationID: UUID) async throws {
        // Remove from source.
        try await remove(taskID: task.id, in: task.sourceFileID)
        // Append to destination.
        var moved = task
        moved.sourceFileID = destinationID
        _ = try await appendTask(moved, to: destinationID)
    }

    // MARK: - Reorder

    /// Reorder a contiguous "bucket" of tasks within a file so they occupy their
    /// existing slots in the new order given by `taskIDs`.
    ///
    /// - The slots a bucket occupies in the file remain the same; only which task
    ///   sits in which slot changes. Tasks **outside** the bucket (different
    ///   priority, blank-line spacers, etc.) are not moved.
    /// - This is the canonical persistence path for drag-and-drop ordering: the
    ///   file's line order *is* the truth, no `order:` metadata is involved.
    public func reorderTasksInFile(_ fileID: UUID, taskIDs: [TodoTaskID]) async throws {
        try await mutate(taskFileID: fileID) { file in
            // Find each task's current line index in the file.
            var slots: [Int] = []
            var newOrderTasks: [TodoTask] = []
            slots.reserveCapacity(taskIDs.count)
            newOrderTasks.reserveCapacity(taskIDs.count)
            for id in taskIDs {
                guard let idx = file.tasks.firstIndex(where: { $0.id == id }) else { return }
                slots.append(idx)
                newOrderTasks.append(file.tasks[idx])
            }
            // Sort the slots ascending — these are the file positions we'll fill,
            // in their natural top-to-bottom order, with the user's new order.
            let ascendingSlots = slots.sorted()
            for (index, slot) in ascendingSlots.enumerated() {
                var t = newOrderTasks[index]
                t.lineNumber = slot + 1
                file.tasks[slot] = t
            }
        }
    }

    // MARK: - Events

    public func events() -> AsyncStream<RepositoryEvent> {
        AsyncStream<RepositoryEvent> { continuation in
            let id = UUID()
            self.continuations[id] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func emit(_ event: RepositoryEvent) {
        for cont in continuations.values {
            cont.yield(event)
        }
    }

    // MARK: - Helpers

    private func updateLastLoaded(for id: UUID, hash: String) {
        guard let idx = workspace.taskFiles.firstIndex(where: { $0.id == id }) else { return }
        workspace.taskFiles[idx].lastKnownContentHash = hash
        workspace.taskFiles[idx].lastLoadedAt = Date()
    }
}

/// Events emitted by `TaskRepository.events()`.
public enum RepositoryEvent: Sendable, Hashable {
    case fileLoaded(UUID)
    case fileSaved(UUID)
    case workspaceChanged
}

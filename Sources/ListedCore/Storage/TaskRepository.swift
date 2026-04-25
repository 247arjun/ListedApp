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
        serializer: TodoTxtSerializer = TodoTxtSerializer()
    ) {
        self.workspace = workspace
        self.resolver = resolver
        self.io = io
        self.parser = parser
        self.serializer = serializer
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
        if !io.fileExists(at: url) {
            // Treat a missing file as empty content.
            let empty = TodoTxtFile(taskFileID: taskFileID, tasks: [], lineEnding: .lf, hasTrailingNewline: true, contentHash: SHA256Hash.hex(of: ""))
            files[taskFileID] = empty
            updateLastLoaded(for: taskFileID, hash: empty.contentHash)
            emit(.fileLoaded(taskFileID))
            return .loaded(empty)
        }

        let text = try io.readUTF8(at: url)
        let hash = SHA256Hash.hex(of: text)
        if let existing = files[taskFileID], existing.contentHash == hash {
            return .unchanged
        }
        var parsed = TodoTxtFile.parse(text: text, taskFileID: taskFileID, parser: parser)
        parsed.contentHash = hash
        files[taskFileID] = parsed
        updateLastLoaded(for: taskFileID, hash: hash)
        emit(.fileLoaded(taskFileID))
        return .loaded(parsed)
    }

    /// Load every enabled file. Errors per-file are returned but do not abort the batch.
    public func loadAllEnabled() async -> [(UUID, Error)] {
        var errors: [(UUID, Error)] = []
        for tf in enabledTaskFiles() {
            do {
                _ = try await load(taskFileID: tf.id)
            } catch {
                errors.append((tf.id, error))
            }
        }
        return errors
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
        let newText = working.renderAndHash()
        try io.writeUTF8(newText, to: url)
        files[taskFileID] = working
        updateLastLoaded(for: taskFileID, hash: working.contentHash)
        emit(.fileSaved(taskFileID))
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

    // MARK: - Archive

    /// Archive every completed task in `sourceID` into `destinationID`. Returns the
    /// number of tasks moved.
    @discardableResult
    public func archiveCompleted(from sourceID: UUID, to destinationID: UUID) async throws -> Int {
        guard let source = files[sourceID] else { return 0 }
        let completed = source.tasks.filter { $0.isCompleted }
        for task in completed {
            try await moveTask(task, toFileID: destinationID)
        }
        return completed.count
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

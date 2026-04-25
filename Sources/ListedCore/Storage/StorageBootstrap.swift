import Foundation

/// Performs first-launch storage bootstrap and exposes the high-level "set up workspace"
/// flow described in the spec (sections 6.2 / 6.3).
public final class StorageBootstrap: @unchecked Sendable {

    private let resolver: FileURLResolver
    private let io: CoordinatedFileIO

    public init(resolver: FileURLResolver = FileURLResolver(), io: CoordinatedFileIO = CoordinatedFileIO()) {
        self.resolver = resolver
        self.io = io
    }

    public var isICloudAvailable: Bool {
        resolver.iCloudDocumentsURL() != nil
    }

    /// Build a brand-new "Default" workspace using the user's choice of storage.
    public func makeInitialWorkspace(useICloud: Bool) throws -> Workspace {
        let preferICloud = useICloud && isICloudAvailable
        let source = try makeAppManagedSource(useICloud: preferICloud)
        let resolved = try resolver.resolveRoot(for: source)
        defer { resolved.release() }

        // Create todo.txt if it doesn't exist.
        let todoURL = resolved.url.appendingPathComponent("todo.txt")
        if !io.fileExists(at: todoURL) {
            try io.writeUTF8("", to: todoURL)
        }

        let active = TaskFile(
            sourceID: source.id,
            displayName: "todo.txt",
            relativePath: "todo.txt",
            role: .activeTodo,
            sortOrder: 0
        )

        let archive = TaskFile(
            sourceID: source.id,
            displayName: "done.txt",
            relativePath: "done.txt",
            role: .completedArchive,
            isEnabled: false,
            sortOrder: 1
        )

        return Workspace(
            name: "Default",
            fileSources: [source],
            taskFiles: [active, archive],
            defaultTaskFileID: active.id
        )
    }

    /// Create a `FileSource` for either iCloud or local app storage.
    public func makeAppManagedSource(useICloud: Bool) throws -> FileSource {
        if useICloud {
            guard isICloudAvailable else { throw StorageError.iCloudUnavailable }
            return FileSource(
                displayName: "iCloud — Listed",
                kind: .appICloudContainer,
                isDefault: true
            )
        } else {
            return FileSource(
                displayName: "On My Device — Listed",
                kind: .appLocalContainer,
                isDefault: true
            )
        }
    }

    /// Add an external `.txt` file (security-scoped) to a workspace and return the
    /// updated workspace.
    public func addExternalFile(_ url: URL, to workspace: Workspace, role: TaskFileRole = .activeTodo) throws -> Workspace {
        let bookmark = try resolver.makeBookmark(for: url)
        let source = FileSource(
            displayName: url.deletingPathExtension().lastPathComponent,
            kind: .securityScopedFile,
            rootBookmarkData: bookmark,
            rootURLString: url.absoluteString
        )
        let taskFile = TaskFile(
            sourceID: source.id,
            displayName: url.lastPathComponent,
            relativePath: "",
            role: role,
            sortOrder: workspace.taskFiles.count
        )
        var updated = workspace
        updated.fileSources.append(source)
        updated.taskFiles.append(taskFile)
        return updated
    }

    /// Add a folder of `.txt` files (security-scoped) to a workspace. Discovers existing
    /// `.txt` files at the top level and registers each as an active task file.
    public func addExternalFolder(_ url: URL, to workspace: Workspace) throws -> Workspace {
        let bookmark = try resolver.makeBookmark(for: url)
        let source = FileSource(
            displayName: url.lastPathComponent,
            kind: .securityScopedFolder,
            rootBookmarkData: bookmark,
            rootURLString: url.absoluteString
        )

        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let txtFiles = contents.filter { $0.hasSuffix(".txt") }.sorted()

        var taskFiles: [TaskFile] = []
        for (index, name) in txtFiles.enumerated() {
            let role: TaskFileRole = (name == "done.txt") ? .completedArchive : .activeTodo
            taskFiles.append(TaskFile(
                sourceID: source.id,
                displayName: name,
                relativePath: name,
                role: role,
                sortOrder: workspace.taskFiles.count + index
            ))
        }

        var updated = workspace
        updated.fileSources.append(source)
        updated.taskFiles.append(contentsOf: taskFiles)
        return updated
    }
}

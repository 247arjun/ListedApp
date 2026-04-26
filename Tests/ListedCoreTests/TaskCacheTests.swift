import XCTest
@testable import ListedCore

final class TaskCacheTests: XCTestCase {

    private func makeTempEnv() -> (URL, FileURLResolver, TaskCacheStore) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ListedCacheTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let appSupport = tmp.appendingPathComponent("AppSupport", isDirectory: true)

        let resolver = FileURLResolver(
            iCloudRootOverride: { nil },
            localRootOverride: { tmp },
            applicationSupportOverride: { appSupport }
        )
        let cache = TaskCacheStore(resolver: resolver)
        return (tmp, resolver, cache)
    }

    func testCacheRoundTrip() throws {
        let (tmp, _, cache) = makeTempEnv()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let id = UUID()
        XCTAssertNil(cache.cachedText(for: id))

        cache.write("(A) Hello world", for: id)
        XCTAssertEqual(cache.cachedText(for: id), "(A) Hello world")

        cache.write("Updated content\nLine two", for: id)
        XCTAssertEqual(cache.cachedText(for: id), "Updated content\nLine two")
    }

    func testCacheRemove() throws {
        let (tmp, _, cache) = makeTempEnv()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let id = UUID()
        cache.write("Bye", for: id)
        XCTAssertNotNil(cache.cachedText(for: id))
        cache.remove(id)
        XCTAssertNil(cache.cachedText(for: id))
    }

    func testRepositoryWritesCache() async throws {
        let (tmp, resolver, cache) = makeTempEnv()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = FileSource(displayName: "Test", kind: .appLocalContainer)
        let active = TaskFile(sourceID: source.id, displayName: "todo.txt", relativePath: "todo.txt")
        let workspace = Workspace(fileSources: [source], taskFiles: [active], defaultTaskFileID: active.id)
        let repo = TaskRepository(workspace: workspace, resolver: resolver, cache: cache)

        // Pre-create the file on disk.
        try "Existing line\n".write(to: tmp.appendingPathComponent("todo.txt"), atomically: true, encoding: .utf8)

        try await repo.load(taskFileID: active.id)
        XCTAssertEqual(cache.cachedText(for: active.id), "Existing line\n")

        // Now write through the repo and confirm cache is updated.
        let task = TaskOperations.make(description: "New task", sourceFileID: active.id, lineNumber: 1, addUID: false, addCreationDate: false)
        _ = try await repo.appendTask(task, to: active.id)

        let cached = cache.cachedText(for: active.id) ?? ""
        XCTAssertTrue(cached.contains("New task"), "cache after write was: \(cached)")
    }

    func testRepositorySeedAvoidsDiskRead() async throws {
        let (tmp, resolver, cache) = makeTempEnv()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = FileSource(displayName: "Test", kind: .appLocalContainer)
        let active = TaskFile(sourceID: source.id, displayName: "todo.txt", relativePath: "todo.txt")
        let workspace = Workspace(fileSources: [source], taskFiles: [active], defaultTaskFileID: active.id)
        let repo = TaskRepository(workspace: workspace, resolver: resolver, cache: cache)

        // Note: there is NO file on disk. Seeding with a parsed file should still
        // make `loadedFiles()` return content — proving the launch path doesn't
        // require iCloud / disk to be available.
        let seeded = TodoTxtFile.parse(text: "Cached only\n", taskFileID: active.id)
        await repo.seed(files: [seeded])

        let snapshot = await repo.loadedFiles()
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot[0].tasks.first?.description, "Cached only")
    }
}

import XCTest
@testable import ListedCore

final class TaskRepositoryTests: XCTestCase {

    private func makeTempWorkspace() -> (Workspace, URL, FileURLResolver) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ListedTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let resolver = FileURLResolver(
            iCloudRootOverride: { nil },
            localRootOverride: { tmp }
        )
        let source = FileSource(displayName: "Test Local", kind: .appLocalContainer)
        let active = TaskFile(sourceID: source.id, displayName: "todo.txt", relativePath: "todo.txt")
        let archive = TaskFile(sourceID: source.id, displayName: "done.txt", relativePath: "done.txt", role: .completedArchive)
        let workspace = Workspace(fileSources: [source], taskFiles: [active, archive], defaultTaskFileID: active.id)
        return (workspace, tmp, resolver)
    }

    func testAppendAndPersist() async throws {
        let (workspace, tmp, resolver) = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repo = TaskRepository(workspace: workspace, resolver: resolver)
        let activeID = workspace.taskFiles[0].id

        try await repo.load(taskFileID: activeID)
        let task = TaskOperations.make(
            description: "Buy milk",
            sourceFileID: activeID,
            lineNumber: 1,
            addUID: false,
            addCreationDate: false
        )
        _ = try await repo.appendTask(task, to: activeID)

        let onDisk = try String(contentsOf: tmp.appendingPathComponent("todo.txt"), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("Buy milk"))
    }

    func testCompleteArchiveMovesLine() async throws {
        let (workspace, tmp, resolver) = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repo = TaskRepository(workspace: workspace, resolver: resolver)
        let activeID = workspace.taskFiles[0].id
        let archiveID = workspace.taskFiles[1].id

        try await repo.load(taskFileID: activeID)
        try await repo.load(taskFileID: archiveID)

        var task = TaskOperations.make(description: "Pay bill", sourceFileID: activeID, lineNumber: 1, addUID: false, addCreationDate: false)
        task = try await repo.appendTask(task, to: activeID)

        let completed = TaskOperations.complete(task, on: LocalDate(year: 2026, month: 4, day: 25))
        try await repo.replace(task: completed)
        let movedCount = try await repo.archiveCompleted(from: activeID, to: archiveID)
        XCTAssertEqual(movedCount, 1)

        let activeText = try String(contentsOf: tmp.appendingPathComponent("todo.txt"), encoding: .utf8)
        let archiveText = try String(contentsOf: tmp.appendingPathComponent("done.txt"), encoding: .utf8)
        XCTAssertFalse(activeText.contains("Pay bill"))
        XCTAssertTrue(archiveText.contains("Pay bill"))
    }

    func testReloadDetectsExternalEdit() async throws {
        let (workspace, tmp, resolver) = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repo = TaskRepository(workspace: workspace, resolver: resolver)
        let activeID = workspace.taskFiles[0].id

        // Pre-populate via the repo, then mutate on disk.
        try "Initial task\n".write(to: tmp.appendingPathComponent("todo.txt"), atomically: true, encoding: .utf8)
        let firstLoad = try await repo.load(taskFileID: activeID)
        if case .loaded(let f) = firstLoad {
            XCTAssertEqual(f.tasks.count, 1)
        } else {
            XCTFail("expected first load to return content")
        }

        try "Modified task\n".write(to: tmp.appendingPathComponent("todo.txt"), atomically: true, encoding: .utf8)
        let second = try await repo.load(taskFileID: activeID)
        switch second {
        case .loaded(let f):
            XCTAssertEqual(f.tasks.first?.description, "Modified task")
        case .unchanged:
            XCTFail("expected second load to detect change")
        }
    }

    func testReorderTasksRewritesFileLineOrder() async throws {
        let (workspace, tmp, resolver) = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repo = TaskRepository(workspace: workspace, resolver: resolver)
        let activeID = workspace.taskFiles[0].id
        let url = tmp.appendingPathComponent("todo.txt")

        // Three (B) tasks with stable UIDs interleaved with one (A) task.
        try """
        (A) Top priority uid:01A
        (B) Beta one uid:01B1
        (B) Beta two uid:01B2
        (B) Beta three uid:01B3
        """.write(to: url, atomically: true, encoding: .utf8)

        try await repo.load(taskFileID: activeID)
        let fileOpt = await repo.file(forTaskFileID: activeID)
        let file = try XCTUnwrap(fileOpt)
        let b1 = try XCTUnwrap(file.task(withUID: "01B1"))
        let b2 = try XCTUnwrap(file.task(withUID: "01B2"))
        let b3 = try XCTUnwrap(file.task(withUID: "01B3"))

        // Reorder the (B) bucket: B3, B1, B2 (B2 stays last among B's).
        try await repo.reorderTasksInFile(activeID, taskIDs: [b3.id, b1.id, b2.id])

        let onDisk = try String(contentsOf: url, encoding: .utf8)
        let lines = onDisk.split(separator: "\n").map(String.init)
        // (A) row remains in slot 0; (B) slots get the new order top→bottom.
        XCTAssertEqual(lines[0], "(A) Top priority uid:01A")
        XCTAssertEqual(lines[1], "(B) Beta three uid:01B3")
        XCTAssertEqual(lines[2], "(B) Beta one uid:01B1")
        XCTAssertEqual(lines[3], "(B) Beta two uid:01B2")
    }
}

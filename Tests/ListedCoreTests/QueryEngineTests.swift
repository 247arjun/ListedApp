import XCTest
@testable import ListedCore

final class QueryEngineTests: XCTestCase {
    private let parser = TodoTxtParser()
    private let engine = QueryEngine()

    private func makeFile(_ text: String) -> (TodoTxtFile, TaskFile) {
        let id = UUID()
        let file = TodoTxtFile.parse(text: text, taskFileID: id, parser: parser)
        let tf = TaskFile(id: id, sourceID: UUID(), displayName: "todo.txt", relativePath: "todo.txt")
        return (file, tf)
    }

    func testTodaySmartList() {
        let today = LocalDate(year: 2026, month: 4, day: 25)
        let text = """
        Buy milk due:\(today.iso8601)
        Pay bill due:\(today.adding(days: -1).iso8601)
        Future task due:\(today.adding(days: 5).iso8601)
        Random task
        """
        let (file, tf) = makeFile(text)
        let q = TaskQuery(scope: .smartList(.today))
        let results = engine.run(query: q, files: [file], taskFiles: [tf], today: today)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.dueDate != nil })
    }

    func testProjectScope() {
        let text = """
        Task one +Work
        Task two +Home
        Task three +Work
        """
        let (file, tf) = makeFile(text)
        let q = TaskQuery(scope: .project("Work"))
        let results = engine.run(query: q, files: [file], taskFiles: [tf])
        XCTAssertEqual(results.count, 2)
    }

    func testFreeTextSearch() {
        let text = """
        Buy milk
        Pay electricity bill
        Walk dog
        """
        let (file, tf) = makeFile(text)
        let q = TaskQuery(scope: .all, searchText: "bill")
        let results = engine.run(query: q, files: [file], taskFiles: [tf])
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].rawLine.contains("electricity"))
    }

    func testIsDoneFilter() {
        let text = """
        Active one
        x 2026-04-20 Done one
        Active two
        """
        let (file, tf) = makeFile(text)
        let q = TaskQuery(scope: .all, searchText: "is:done", includeCompleted: true)
        let results = engine.run(query: q, files: [file], taskFiles: [tf])
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isCompleted)
    }

    func testThresholdHidesFutureTasks() {
        let today = LocalDate(year: 2026, month: 4, day: 25)
        let text = """
        Hidden t:\(today.adding(days: 5).iso8601)
        Visible
        """
        let (file, tf) = makeFile(text)
        let q = TaskQuery(scope: .all)
        let results = engine.run(query: q, files: [file], taskFiles: [tf], today: today)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].displayTitle, "Visible")
    }
}

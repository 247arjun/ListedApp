import XCTest
@testable import ListedCore

final class TodoTxtParserTests: XCTestCase {
    private let parser = TodoTxtParser()
    private let fileID = UUID()

    private func parse(_ line: String) -> TodoTask {
        parser.parse(line: line, lineNumber: 1, sourceFileID: fileID)
    }

    // MARK: - Basic

    func testBasicTask() {
        let t = parse("Buy milk")
        XCTAssertFalse(t.isCompleted)
        XCTAssertNil(t.priority)
        XCTAssertNil(t.creationDate)
        XCTAssertEqual(t.description, "Buy milk")
    }

    func testBlankLineIsBlank() {
        XCTAssertTrue(parse("").isBlank)
        XCTAssertTrue(parse("   ").isBlank)
    }

    // MARK: - Priority

    func testPriority() {
        let t = parse("(A) Buy milk")
        XCTAssertEqual(t.priority, "A")
        XCTAssertEqual(t.description, "Buy milk")
    }

    func testInvalidPriorityLowercase() {
        let t = parse("(a) Buy milk")
        XCTAssertNil(t.priority)
        XCTAssertEqual(t.description, "(a) Buy milk")
    }

    func testInvalidPriorityWithoutSpace() {
        let t = parse("(A)Buy milk")
        XCTAssertNil(t.priority)
    }

    // MARK: - Dates

    func testCreationDateOnly() {
        let t = parse("2026-04-25 Read chapter 5")
        XCTAssertEqual(t.creationDate, LocalDate(year: 2026, month: 4, day: 25))
        XCTAssertEqual(t.description, "Read chapter 5")
    }

    func testPriorityAndCreationDate() {
        let t = parse("(A) 2026-04-25 Write tests")
        XCTAssertEqual(t.priority, "A")
        XCTAssertEqual(t.creationDate, LocalDate(year: 2026, month: 4, day: 25))
        XCTAssertEqual(t.description, "Write tests")
    }

    // MARK: - Projects, contexts, metadata

    func testProjectAndContext() {
        let t = parse("Call bank +Finance @phone")
        XCTAssertEqual(t.projects, ["Finance"])
        XCTAssertEqual(t.contexts, ["phone"])
    }

    func testMultipleProjects() {
        let t = parse("Refactor +Listed +Storage @mac")
        XCTAssertEqual(t.projects, ["Listed", "Storage"])
        XCTAssertEqual(t.contexts, ["mac"])
    }

    func testDueDateMetadata() {
        let t = parse("Pay bill due:2026-04-30")
        XCTAssertEqual(t.dueDate, LocalDate(year: 2026, month: 4, day: 30))
        XCTAssertEqual(t.metadata["due"], "2026-04-30")
    }

    func testThresholdAndRecurrence() {
        let t = parse("Brew tea t:2026-05-01 rec:1w")
        XCTAssertEqual(t.thresholdDate, LocalDate(year: 2026, month: 5, day: 1))
        XCTAssertEqual(t.recurrence, "1w")
    }

    func testUnknownMetadataPreserved() {
        let t = parse("Task foo:bar")
        XCTAssertEqual(t.metadata["foo"], "bar")
    }

    func testURLNotTreatedAsMetadata() {
        let t = parse("Read https://example.com/a:b")
        XCTAssertNil(t.metadata["https"])
    }

    // MARK: - Completion

    func testCompletedTask() {
        let t = parse("x 2026-04-25 Write tests")
        XCTAssertTrue(t.isCompleted)
        XCTAssertEqual(t.completionDate, LocalDate(year: 2026, month: 4, day: 25))
        XCTAssertEqual(t.description, "Write tests")
    }

    func testCompletedWithCreationDate() {
        let t = parse("x 2026-04-25 2026-04-20 Write tests")
        XCTAssertTrue(t.isCompleted)
        XCTAssertEqual(t.completionDate, LocalDate(year: 2026, month: 4, day: 25))
        XCTAssertEqual(t.creationDate, LocalDate(year: 2026, month: 4, day: 20))
    }

    func testCompletedPreservedPriority() {
        let t = parse("x 2026-04-25 Write tests +Work pri:A")
        XCTAssertEqual(t.preservedPriority, "A")
    }

    func testUppercaseXIsNotCompletion() {
        let t = parse("X Buy milk")
        XCTAssertFalse(t.isCompleted)
    }

    // MARK: - UID & parent

    func testUIDIsExtracted() {
        let t = parse("Task uid:01JABC")
        XCTAssertEqual(t.uid, "01JABC")
    }

    func testParentIsExtracted() {
        let t = parse("Task parent:01JPARENT uid:01JCHILD")
        XCTAssertEqual(t.parentUID, "01JPARENT")
        XCTAssertEqual(t.uid, "01JCHILD")
    }
}

import XCTest
@testable import ListedCore

final class TodoTxtSerializerTests: XCTestCase {
    private let parser = TodoTxtParser()
    private let serializer = TodoTxtSerializer()
    private let fileID = UUID()

    private func parse(_ line: String) -> TodoTask {
        parser.parse(line: line, lineNumber: 1, sourceFileID: fileID)
    }

    func testRoundTripBasic() {
        let line = "Buy milk"
        let task = parse(line)
        XCTAssertEqual(serializer.serialize(task, mode: .rebuild), line)
    }

    func testRoundTripPriorityProjectContextDue() {
        let line = "(A) 2026-04-25 Write tests +Work @mac due:2026-04-27 uid:01JABC"
        let task = parse(line)
        let out = serializer.serialize(task, mode: .rebuild)
        XCTAssertEqual(out, line)
    }

    func testRoundTripCompletedPreservesPriority() {
        let line = "x 2026-04-25 2026-04-20 Write tests +Work @mac due:2026-04-27 uid:01JABC pri:A"
        let task = parse(line)
        XCTAssertEqual(serializer.serialize(task, mode: .rebuild), line)
    }

    func testCompleteOperationRewritesCorrectly() {
        var task = parse("(A) 2026-04-20 Write tests +Work @mac due:2026-04-27 uid:01JABC")
        task = TaskOperations.complete(task, on: LocalDate(year: 2026, month: 4, day: 25))
        let serialized = serializer.serialize(task, mode: .rebuild)
        XCTAssertEqual(
            serialized,
            "x 2026-04-25 2026-04-20 Write tests +Work @mac due:2026-04-27 uid:01JABC pri:A"
        )
    }

    func testReopenOperationReverses() {
        let original = "(A) 2026-04-20 Write tests +Work @mac due:2026-04-27 uid:01JABC"
        var task = parse(original)
        task = TaskOperations.complete(task, on: LocalDate(year: 2026, month: 4, day: 25))
        task = TaskOperations.reopen(task)
        XCTAssertEqual(serializer.serialize(task, mode: .rebuild), original)
    }

    func testSetDueDateAddsTokenOnce() {
        var task = parse("Pay bill")
        task = TaskOperations.setDueDate(task, to: LocalDate(year: 2026, month: 4, day: 30))
        XCTAssertEqual(serializer.serialize(task, mode: .rebuild), "Pay bill due:2026-04-30")
        // Setting again must not duplicate the token.
        task = TaskOperations.setDueDate(task, to: LocalDate(year: 2026, month: 5, day: 1))
        XCTAssertEqual(serializer.serialize(task, mode: .rebuild), "Pay bill due:2026-05-01")
    }

    func testRemoveDueDate() {
        var task = parse("Pay bill due:2026-04-30")
        task = TaskOperations.setDueDate(task, to: nil)
        XCTAssertEqual(serializer.serialize(task, mode: .rebuild), "Pay bill")
    }

    func testUnknownMetadataPreservedThroughRoundTrip() {
        let line = "Task foo:bar baz:qux uid:01JABC"
        let task = parse(line)
        let out = serializer.serialize(task, mode: .rebuild)
        // Order of unknown metadata is preserved, managed metadata (uid) emitted last.
        XCTAssertEqual(out, "Task foo:bar baz:qux uid:01JABC")
    }

    func testPreserveRawIfPossible() {
        let line = "  Weird   formatting   uid:01JABC"
        let task = parse(line)
        XCTAssertEqual(serializer.serialize(task, mode: .preserveRawIfPossible), line)
    }
}

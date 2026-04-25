import XCTest
@testable import ListedCore

final class TodoTxtFileTests: XCTestCase {
    private let fileID = UUID()

    func testParseAndRenderRoundTrip() {
        let text = """
        (A) 2026-04-25 Write tests +Work @mac due:2026-04-27
        Buy milk
        x 2026-04-24 Old task uid:01ABC
        """
        let file = TodoTxtFile.parse(text: text, taskFileID: fileID)
        XCTAssertEqual(file.tasks.count, 3)
        XCTAssertEqual(file.lineEnding, .lf)
        XCTAssertFalse(file.hasTrailingNewline)
        XCTAssertEqual(file.render(), text)
    }

    func testTrailingNewlinePreserved() {
        let text = "Buy milk\nPay bill\n"
        let file = TodoTxtFile.parse(text: text, taskFileID: fileID)
        XCTAssertEqual(file.tasks.count, 2)
        XCTAssertTrue(file.hasTrailingNewline)
        XCTAssertEqual(file.render(), text)
    }

    func testCRLFPreserved() {
        let text = "Buy milk\r\nPay bill\r\n"
        let file = TodoTxtFile.parse(text: text, taskFileID: fileID)
        XCTAssertEqual(file.lineEnding, .crlf)
        XCTAssertEqual(file.render(), text)
    }

    func testBlankLinesPreserved() {
        let text = "First\n\nSecond"
        let file = TodoTxtFile.parse(text: text, taskFileID: fileID)
        XCTAssertEqual(file.tasks.count, 3)
        XCTAssertTrue(file.tasks[1].isBlank)
        XCTAssertEqual(file.render(), text)
    }

    func testHashChangesWhenContentChanges() {
        let a = TodoTxtFile.parse(text: "Buy milk", taskFileID: fileID)
        let b = TodoTxtFile.parse(text: "Buy bread", taskFileID: fileID)
        XCTAssertNotEqual(a.contentHash, b.contentHash)
    }
}

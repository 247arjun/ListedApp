import XCTest
@testable import ListedCore

final class LocalDateTests: XCTestCase {
    func testISO8601() {
        XCTAssertEqual(LocalDate(year: 2026, month: 1, day: 5).iso8601, "2026-01-05")
        XCTAssertEqual(LocalDate(year: 2026, month: 12, day: 31).iso8601, "2026-12-31")
    }

    func testParse() {
        XCTAssertEqual(LocalDate.parse("2026-04-25"), LocalDate(year: 2026, month: 4, day: 25))
        XCTAssertNil(LocalDate.parse("2026/04/25"))
        XCTAssertNil(LocalDate.parse("2026-13-01"))
        XCTAssertNil(LocalDate.parse("not a date"))
    }

    func testComparable() {
        let a = LocalDate(year: 2026, month: 4, day: 1)
        let b = LocalDate(year: 2026, month: 4, day: 2)
        let c = LocalDate(year: 2026, month: 5, day: 1)
        XCTAssertLessThan(a, b)
        XCTAssertLessThan(b, c)
    }

    func testAdding() {
        let d = LocalDate(year: 2026, month: 4, day: 30)
        XCTAssertEqual(d.adding(days: 1), LocalDate(year: 2026, month: 5, day: 1))
        XCTAssertEqual(d.adding(days: -30), LocalDate(year: 2026, month: 3, day: 31))
    }
}

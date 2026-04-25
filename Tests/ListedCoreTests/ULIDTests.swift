import XCTest
@testable import ListedCore

final class ULIDTests: XCTestCase {
    func testGenerateProduces26Chars() {
        let id = ULID.generate()
        XCTAssertEqual(id.count, 26)
        XCTAssertTrue(ULID.isValid(id))
    }

    func testIsValidRejectsBadInputs() {
        XCTAssertFalse(ULID.isValid("short"))
        XCTAssertFalse(ULID.isValid(String(repeating: "U", count: 26)))
    }

    func testTimestampPrefixIsLexicographicallyMonotone() {
        let earlier = ULID.generate(at: Date(timeIntervalSince1970: 1000))
        let later = ULID.generate(at: Date(timeIntervalSince1970: 2000))
        XCTAssertLessThan(earlier.prefix(10), later.prefix(10))
    }
}

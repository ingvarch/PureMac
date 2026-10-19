import XCTest
import TerminalUI

final class TermTests: XCTestCase {
    func testANSIAndUnicodeDisplayWidth() {
        XCTAssertEqual(Term.displayWidth("\u{1B}[31mclean\u{1B}[0m"), 5)
        XCTAssertEqual(Term.displayWidth("界"), 2)
        XCTAssertEqual(Term.displayWidth("a\u{301}"), 1)
    }

    func testTerminalControlCharactersAreSanitized() {
        XCTAssertEqual(Term.sanitize("safe\u{1B}[2Jname\n"), "safe�[2Jname�")
        XCTAssertEqual(Term.sanitize("one\ttwo"), "one two")
    }

    func testMiddleTruncationRespectsVisibleWidth() {
        let value = Term.truncate("/Users/example/Library/Caches/tool", to: 18, middle: true)
        XCTAssertLessThanOrEqual(Term.displayWidth(value), 18)
        XCTAssertTrue(value.contains("…"))
        XCTAssertTrue(value.hasPrefix("/Users/e"))
        XCTAssertTrue(value.hasSuffix("ches/tool"))
    }

    func testTermBarOutputIsUnchanged() {
        XCTAssertEqual(Term.bar(fraction: 0.25, width: 8), "██░░░░░░")
        XCTAssertEqual(Term.bar(fraction: 3, width: 3), "███")
        XCTAssertEqual(Term.bar(fraction: 0.5, width: -2), "")
        XCTAssertEqual(Term.bar(fraction: 0.5).count, 24)
    }
}

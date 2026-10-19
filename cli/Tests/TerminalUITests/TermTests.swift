import XCTest
@testable import TerminalUI

final class TermTests: XCTestCase {
    func testANSIAndUnicodeDisplayWidth() {
        XCTAssertEqual(Term.displayWidth("\u{1B}[31mclean\u{1B}[0m"), 5)
        XCTAssertEqual(Term.displayWidth("界"), 2)
        XCTAssertEqual(Term.displayWidth("a\u{301}"), 1)
    }

    func testSpanWidthSumsSanitizedText() {
        XCTAssertEqual(Term.displayWidth([Span("ab"), Span("界")]), 4)
        XCTAssertEqual(Term.displayWidth([Span("a\u{1B}[2Jb")]), 6)
        XCTAssertEqual(Term.displayWidth([Span]()), 0)
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

    func testWrapPreservesEveryCharacter() {
        let path = "/Users/example/a folder/with/a/very-long-name/file.bin"
        let lines = Term.wrap(path, width: 11)

        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertEqual(lines.joined(), path)
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) <= 11 })
    }

    func testWordWrapKeepsSpaceRunsWithinALine() {
        XCTAssertEqual(Term.wordWrap("one   two  three", width: 12), ["one   two", "three"])
        XCTAssertEqual(Term.wordWrap("1 skipped  protected or ignored", width: 40), ["1 skipped  protected or ignored"])
    }

    func testWordWrapDropsSpaceRunAtALineBreak() {
        XCTAssertEqual(Term.wordWrap("one   two  three", width: 7), ["one", "two", "three"])
    }

    func testWordWrapEmptyParagraphIsOneEmptyRow() {
        XCTAssertEqual(Term.wordWrap("", width: 10), [""])
    }

    func testWordWrapHardBreaksLongWord() {
        XCTAssertEqual(Term.wordWrap("ab abcdefg", width: 3), ["ab", "abc", "def", "g"])
    }
}

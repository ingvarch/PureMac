import XCTest
@testable import TerminalUI

final class TerminalSessionTests: XCTestCase {
    private let esc = "\u{1B}"

    func testFrameClearsBelowOnlyWhenFrameIsShorterThanScreen() {
        XCTAssertTrue(TerminalSession.frame(lines: ["a", "b"], height: 3).hasSuffix("\(esc)[J"))
        XCTAssertFalse(TerminalSession.frame(lines: ["a", "b", "c"], height: 3).hasSuffix("\(esc)[J"))
        XCTAssertTrue(TerminalSession.frame(lines: ["a", "b", "c", "d"], height: 3).contains("c"))
        XCTAssertFalse(TerminalSession.frame(lines: ["a", "b", "c", "d"], height: 3).contains("d"))
    }
}

import XCTest
import TerminalUI
@testable import puremac

final class ExploreConfirmationTests: XCTestCase {
    func testEnterActivatesTheFocusedButton() {
        var model = ExploreConfirmation()
        XCTAssertEqual(model.handle(.enter), .start)
        XCTAssertNil(model.handle(.left))
        XCTAssertEqual(model.handle(.enter), .back)
    }

    func testLeftRightClampAndTabCycles() {
        var model = ExploreConfirmation()
        XCTAssertNil(model.handle(.right))
        XCTAssertEqual(model.handle(.enter), .start)
        XCTAssertNil(model.handle(.left))
        XCTAssertNil(model.handle(.left))
        XCTAssertEqual(model.handle(.enter), .back)
        XCTAssertNil(model.handle(.tab))
        XCTAssertEqual(model.handle(.enter), .start)
        XCTAssertNil(model.handle(.tab))
        XCTAssertEqual(model.handle(.enter), .back)
    }

    func testEscapeQAndNGoBackFromAnyFocus() {
        for key in [TerminalKey.escape, .character("q"), .character("Q"), .character("n"), .character("N")] {
            var model = ExploreConfirmation()
            XCTAssertEqual(model.handle(key), .back)
        }
    }

    func testSStartsFromAnyFocus() {
        var model = ExploreConfirmation()
        _ = model.handle(.left)
        XCTAssertEqual(model.handle(.character("s")), .start)
        XCTAssertEqual(model.handle(.character("S")), .start)
    }

    func testOtherKeysDoNothing() {
        var model = ExploreConfirmation()
        for key in [TerminalKey.up, .down, .space, .character("x"), .character("y")] {
            XCTAssertNil(model.handle(key))
        }
        XCTAssertEqual(model.handle(.enter), .start)
    }

    func testRendersTheDialogOverTheFadedMenu() {
        let buffer = ExploreConfirmation().render(width: 80, height: 24)
        let lines = buffer.plainLines()
        XCTAssertEqual(lines.count, 24)
        XCTAssertTrue(lines.contains { $0.contains("Explore your home folder?") })
        XCTAssertTrue(lines.contains { $0.contains("Measuring every folder can take a few minutes.") })
        XCTAssertTrue(lines.contains { $0.contains("[ Cancel ]  › Start ‹") })
        XCTAssertTrue(lines.contains { $0.contains("Enter select  Esc back") })
        let menuRow = lines.firstIndex { $0.contains("Clean caches") }
        XCTAssertNotNil(menuRow)
        XCTAssertEqual(buffer[2, menuRow ?? 0].style, TextStyle(dim: true))
    }

    func testFocusFollowsTheModel() {
        var model = ExploreConfirmation()
        _ = model.handle(.left)
        let lines = model.render(width: 80, height: 24).plainLines()
        XCTAssertTrue(lines.contains { $0.contains("› Cancel ‹  [ Start ]") })
    }

    func testFitsTheMinimumSize() {
        let lines = ExploreConfirmation().render(width: 40, height: 12).plainLines()
        XCTAssertEqual(lines.count, 12)
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == 40 })
        XCTAssertTrue(lines.contains { $0.contains("Enter select  Esc back") })
    }

    func testBelowTheMinimumSizeShowsWhatEscDoes() {
        let lines = ExploreConfirmation().render(width: 39, height: 11).plainLines()
        XCTAssertTrue(lines.contains { $0.contains("Esc back") })
    }
}

import XCTest
@testable import puremac
import TerminalUI

final class InteractiveScreensTests: XCTestCase {
    func testReviewStartsWithNothingSelected() {
        let model = InteractiveReviewModel(categories: fixtureCategories())
        XCTAssertEqual(model.selectedCount, 0)
        XCTAssertEqual(model.selectedBytes, 0)
        XCTAssertEqual(model.matchingAddresses.count, 3)
    }

    func testReviewSelectionAndSearchPreserveExactItems() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.toggleFocused()
        model.move(1)
        model.toggleFocused()
        XCTAssertEqual(model.selectedCount, 2)
        XCTAssertEqual(model.selectedBytes, 3_000)

        model.updateQuery("second")
        XCTAssertEqual(model.matchingAddresses.count, 1)
        XCTAssertEqual(model.item(at: model.matchingAddresses[0]).path, "/tmp/second")

        model.selectNone()
        model.selectAllMatching()
        XCTAssertEqual(model.selectedCount, 1)
        XCTAssertEqual(model.selectedResult()[0].selectedItems.map(\.path), ["/tmp/second"])
    }

    func testReviewRequiresSelectionBeforeFinalReview() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        XCTAssertFalse(model.beginReview())
        XCTAssertFalse(model.isReviewing)
        XCTAssertFalse(model.status.isEmpty)

        model.toggleFocused()
        XCTAssertTrue(model.beginReview())
        XCTAssertTrue(model.isReviewing)
    }

    func testReviewRenderIsBoundedAndKeepsControlsVisible() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.selectAllMatching()
        for (width, height) in [(40, 12), (58, 14), (80, 24)] {
            let lines = renderReview(model, width: width, height: height).plainLines()

            XCTAssertEqual(lines.count, height)
            XCTAssertTrue(lines.contains { $0.contains("Space toggle") })
            XCTAssertTrue(lines.contains { $0.contains("Enter review") })
            XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == width })
        }
    }

    func testReviewWindowShowsTitleAndSelectionSummaryInTopBorder() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.toggleFocused()
        let lines = renderReview(model, width: 80, height: 24).plainLines()
        XCTAssertTrue(lines[0].hasPrefix("╭─ Review removable files "))
        XCTAssertTrue(lines[0].hasSuffix(" 1 selected · 1 KB ─╮"))
        XCTAssertFalse(lines.contains { $0.contains("PUREMAC") })
    }

    func testReviewHeaderFitsFortyColumnsWithDifferentCountsAndSizes() {
        let categories = [
            CategoryScan(
                id: "cache",
                title: "Caches",
                groups: [
                    ToolGroup(
                        tool: "Applications",
                        items: [
                            ScanItem(path: "/tmp/one", sizeBytes: 138_300, modified: nil),
                            ScanItem(path: "/tmp/two", sizeBytes: 1_000, modified: nil)
                        ]
                    )
                ]
            )
        ]
        let lines = renderReview(InteractiveReviewModel(categories: categories), width: 40, height: 12).plainLines()

        XCTAssertTrue(lines[0].contains("0 selected"))
        XCTAssertTrue(lines[1].contains("2 shown"))
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == 40 })
    }

    func testReviewFirstRowShowsFoundSummaryDimWhenIdle() {
        let buffer = renderReview(InteractiveReviewModel(categories: fixtureCategories()), width: 80, height: 24)
        XCTAssertTrue(buffer.plainLines()[1].hasPrefix("│ 3 shown · 6 KB"))
        XCTAssertEqual(buffer[2, 1].style, TextStyle(dim: true))
    }

    func testReviewFirstRowShowsSearchFieldWithCursorAndRightAlignedSummary() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.isSearching = true
        model.updateQuery("sec")
        let buffer = renderReview(model, width: 80, height: 24)
        let line = buffer.plainLines()[1]
        XCTAssertTrue(line.hasPrefix("│ Search  sec "))
        XCTAssertTrue(line.hasSuffix("1 shown · 6 KB │"))
        XCTAssertEqual(buffer[2, 1].style, TextStyle(color: .cyan))
        XCTAssertEqual(buffer[13, 1].style, TextStyle(inverse: true))
        XCTAssertEqual(buffer[line.count - 4, 1].style, TextStyle(dim: true))
    }

    func testReviewFirstRowShowsStatusInYellowAndFilterDim() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.selectAllMatching()
        var buffer = renderReview(model, width: 80, height: 24)
        XCTAssertTrue(buffer.plainLines()[1].hasPrefix("│ Selected visible items"))
        XCTAssertEqual(buffer[2, 1].style, TextStyle(color: .yellow))

        model.updateQuery("first")
        buffer = renderReview(model, width: 80, height: 24)
        XCTAssertTrue(buffer.plainLines()[1].hasPrefix("│ Filter  first"))
        XCTAssertEqual(buffer[2, 1].style, TextStyle(dim: true))
        XCTAssertEqual(buffer[10, 1].style, TextStyle(dim: true))
    }

    func testReviewFirstRowOmitsSummaryWhenItDoesNotFit() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.isSearching = true
        model.updateQuery(String(repeating: "x", count: 30))
        let line = renderReview(model, width: 40, height: 12).plainLines()[1]
        XCTAssertFalse(line.contains("shown"))
    }

    func testReviewRowsShowCategoryGroupAndItemsWithFocus() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.toggleFocused()
        let lines = renderReview(model, width: 60, height: 24).plainLines()
        XCTAssertEqual(lines[2], "│ Developer" + String(repeating: " ", count: 48) + "│")
        XCTAssertTrue(lines[3].hasPrefix("│ Build caches"))
        XCTAssertTrue(lines[3].hasSuffix("2 items │"))
        XCTAssertTrue(lines[4].hasPrefix("│ › ● 1 KB       /tmp/first"))
        XCTAssertTrue(lines[5].hasPrefix("│   ○ 2 KB       /tmp/second"))
        XCTAssertTrue(lines[6].hasSuffix("1 item │"))
    }

    func testReviewRowsStyleCategoryGroupAndFocusedItem() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.toggleFocused()
        let buffer = renderReview(model, width: 60, height: 24)
        XCTAssertEqual(buffer[2, 2].style, TextStyle(bold: true))
        XCTAssertEqual(buffer[2, 3].style, TextStyle(dim: true))
        XCTAssertEqual(buffer[56, 3].style, TextStyle(dim: true))
        XCTAssertEqual(buffer[2, 4].style, TextStyle(color: .cyan, inverse: true))
        XCTAssertEqual(buffer[4, 4].style, TextStyle(color: .cyan, inverse: true))
        XCTAssertEqual(buffer[16, 4].style, TextStyle(inverse: true))
        XCTAssertEqual(buffer[55, 4].style, TextStyle(inverse: true))
        XCTAssertEqual(buffer[4, 5].style, TextStyle(dim: true))
        XCTAssertEqual(buffer[16, 5].style, .plain)
    }

    func testReviewItemSizeIsColoredByMagnitudeExceptOnFocusedRow() {
        let sizes: [Int64] = [5, 150_000_000, 2_000_000_000]
        let items = sizes.enumerated().map { ScanItem(path: "/tmp/\($0.offset)", sizeBytes: $0.element, modified: nil, selected: false) }
        var model = InteractiveReviewModel(categories: [
            CategoryScan(id: "c", title: "C", groups: [ToolGroup(tool: "T", items: items)])
        ])
        model.selectAllMatching()
        model.move(2)
        let buffer = renderReview(model, width: 60, height: 24)
        XCTAssertEqual(buffer[7, 4].style, TextStyle(color: .green))
        XCTAssertEqual(buffer[7, 5].style, TextStyle(color: .yellow))
        XCTAssertEqual(buffer[7, 6].style, TextStyle(inverse: true))

        XCTAssertTrue(model.beginReview())
        model.move(2)
        let review = renderReview(model, width: 60, height: 24)
        XCTAssertEqual(review[7, 4].style, TextStyle(color: .green))
        XCTAssertEqual(review[7, 5].style, TextStyle(color: .yellow))
        XCTAssertEqual(review[7, 6].style, TextStyle(inverse: true))
    }

    func testReviewFocusedPathLineSitsBelowDividerAndHintsFollow() {
        let lines = renderReview(InteractiveReviewModel(categories: fixtureCategories()), width: 80, height: 24).plainLines()
        let divider = lines.firstIndex { $0.hasPrefix("├") }!
        XCTAssertTrue(lines[divider].hasSuffix("┤"))
        XCTAssertTrue(lines[divider + 1].hasPrefix("│ Path  /tmp/first"))
        XCTAssertTrue(lines[divider + 2].hasPrefix("│ ↑↓ move  ←→ path  Space toggle  A all  N none  / search  Enter review"))
        XCTAssertTrue(lines[divider + 3].hasPrefix("│ Esc/q cancel"))
        XCTAssertTrue(lines[23].hasPrefix("╰"))
    }

    func testReviewShowsNoMatchingPathWhenFilterFindsNothing() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.updateQuery("zzz")
        let lines = renderReview(model, width: 80, height: 24).plainLines()
        XCTAssertTrue(lines.contains { $0.hasPrefix("│ Path  No matching item") })
    }

    func testReviewScrollbarStaysInListRowsAndAppearsOnlyWhenRowsOverflow() {
        let fitting = renderReview(InteractiveReviewModel(categories: fixtureCategories()), width: 40, height: 24)
        XCTAssertFalse(fitting.plainLines().contains { $0.contains("┃") })

        var model = InteractiveReviewModel(categories: manyItemsCategories(30))
        model.moveToEnd()
        let lines = renderReview(model, width: 40, height: 12).plainLines()
        let rowsWithThumb = lines.indices.filter { lines[$0].hasSuffix("┃") }
        XCTAssertFalse(rowsWithThumb.isEmpty)
        XCTAssertTrue(rowsWithThumb.allSatisfy { (2...5).contains($0) })
        XCTAssertTrue(rowsWithThumb.contains(5), "thumb is at the bottom when focus is on the last row")
    }

    func testReviewKeepsFocusedRowVisibleAndCentered() {
        var model = InteractiveReviewModel(categories: manyItemsCategories(30))
        model.move(15)
        let lines = renderReview(model, width: 40, height: 12).plainLines()
        XCTAssertTrue(lines[4].hasPrefix("│ › ") && lines[4].contains("/tmp/item15"))
    }

    func testReviewGroupRowKeepsGapBeforeCountWhenToolNameIsLong() {
        let categories = [
            CategoryScan(
                id: "c",
                title: "Cat",
                groups: [
                    ToolGroup(
                        tool: String(repeating: "T", count: 60),
                        items: (0..<12).map { ScanItem(path: "/tmp/i\($0)", sizeBytes: 1, modified: nil) }
                    )
                ]
            )
        ]
        let lines = renderReview(InteractiveReviewModel(categories: categories), width: 40, height: 12).plainLines()
        let group = lines[3]
        XCTAssertTrue(group.contains("…"))
        XCTAssertTrue(group.hasSuffix(" 12 items │"))
        XCTAssertEqual(Term.displayWidth(group), 40)
    }

    func testReviewItemRowTruncatesLongPathInTheMiddle() {
        let path = "/tmp/" + String(repeating: "a", count: 40) + "/" + String(repeating: "b", count: 40) + "/end"
        let categories = [
            CategoryScan(id: "c", title: "Cat", groups: [
                ToolGroup(tool: "Tool", items: [ScanItem(path: path, sizeBytes: 1, modified: nil)])
            ])
        ]
        let line = renderReview(InteractiveReviewModel(categories: categories), width: 40, height: 12).plainLines()[4]
        XCTAssertEqual(Term.displayWidth(line), 40)
        XCTAssertTrue(line.contains("a…"))
        XCTAssertTrue(line.contains("…b") || line.contains("/end"))
        XCTAssertFalse(line.hasSuffix("…│"))
    }

    func testFinalReviewControlsFitAtMinimumSupportedWidth() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.selectAllMatching()
        XCTAssertTrue(model.beginReview())
        let lines = renderReview(model, width: 40, height: 12).plainLines()
        XCTAssertEqual(lines.count, 12)
        XCTAssertTrue(lines.contains { $0.contains("Enter confirm") })
        XCTAssertTrue(lines.contains { $0.contains("q cancel") })
        XCTAssertTrue(lines.contains { $0.contains("Command confirmation follows") })
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == 40 })
    }

    func testFinalReviewUsesYellowWindowAndListsOnlySelectedItems() {
        var model = InteractiveReviewModel(categories: fixtureCategories())
        model.toggleFocused()
        XCTAssertTrue(model.beginReview())
        let buffer = renderReview(model, width: 80, height: 24)
        let lines = buffer.plainLines()
        XCTAssertTrue(lines[0].hasPrefix("╭─ Final review "))
        XCTAssertTrue(lines[0].hasSuffix(" 1 selected · 1 KB ─╮"))
        XCTAssertEqual(buffer[0, 0].style, TextStyle(color: .yellow))
        XCTAssertEqual(buffer[3, 0].style, TextStyle(color: .yellow, bold: true))
        XCTAssertTrue(lines.contains { $0.contains("/tmp/first") })
        XCTAssertFalse(lines.contains { $0.contains("/tmp/second") })
        XCTAssertTrue(lines.contains { $0.contains("↑↓ scroll  ←→ path  Enter confirm  Esc edit  q cancel") })
        let confirmation = lines.firstIndex { $0.contains("Command confirmation follows") }!
        XCTAssertEqual(buffer[2, confirmation].style, TextStyle(color: .yellow))
        XCTAssertFalse(lines.contains { $0.contains("Space toggle") })
    }

    func testReviewBelowMinimumUsesTooSmallScreen() {
        let model = InteractiveReviewModel(categories: fixtureCategories())
        let buffer = renderReview(model, width: 18, height: 4)
        XCTAssertEqual(buffer, TooSmallScreen.render(title: "PureMac", exitHint: "Esc/q cancel", width: 18, height: 4))
    }

    func testFocusedPathWindowCanRevealEntirePath() {
        let path = "/Users/example/Library/Caches/application/data"
        let first = InteractiveReview.horizontalWindow(path, offset: 0, width: 20)
        let last = InteractiveReview.horizontalWindow(path, offset: 30, width: 20)

        XCTAssertTrue(first.hasSuffix("›"))
        XCTAssertTrue(last.hasPrefix("‹"))
        XCTAssertLessThanOrEqual(Term.displayWidth(first), 20)
        XCTAssertLessThanOrEqual(Term.displayWidth(last), 20)
    }

    func testMenuSelectionClamps() {
        var model = TerminalMenuModel(optionCount: 8)
        model.move(99)
        XCTAssertEqual(model.selection, 7)
        model.move(-99)
        XCTAssertEqual(model.selection, 0)
        XCTAssertEqual(model.select(number: 7), 6)
        XCTAssertEqual(model.selection, 6)
        XCTAssertNil(model.select(number: 9))
        XCTAssertNil(model.select(number: 0))
    }

    func testMenuRenderPaginatesAndKeepsHintsVisible() {
        let options = menuOptions(8)
        for (width, height) in [(40, 12), (80, 24)] {
            let lines = renderMenu(options: options, selection: 6, width: width, height: height).plainLines()
            XCTAssertEqual(lines.count, height)
            XCTAssertTrue(lines.contains { $0.contains("Tool 7") })
            XCTAssertTrue(lines.contains { $0.contains("Enter open") })
            XCTAssertTrue(lines.contains { $0.contains("1-9 open") })
            XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == width })
        }
    }

    func testMenuRenderCentersFocusedOptionOnPage() {
        let lines = renderMenu(options: menuOptions(8), selection: 6, width: 40, height: 12).plainLines()
        XCTAssertTrue(lines.contains { $0.contains("Tool 6") })
        XCTAssertTrue(lines.contains { $0.contains("Tool 7") })
        XCTAssertFalse(lines.contains { $0.contains("Tool 8") })
        XCTAssertFalse(lines.contains { $0.contains("Tool 5") })
    }

    func testMenuScrollbarTrackStopsAtLastOptionRow() {
        let lines = renderMenu(options: menuOptions(8), selection: 7, width: 40, height: 12).plainLines()
        XCTAssertTrue(lines[6].hasSuffix("┃"), "thumb sits beside the last option detail row")
        XCTAssertFalse(lines[7].hasSuffix("┃"), "spare blank row is not part of the track")
    }

    func testMenuRenderDrawsWindowWithTitleSubtitleAndFocus() {
        let lines = renderMenu(options: menuOptions(2), selection: 0, width: 40, height: 12).plainLines()
        XCTAssertTrue(lines[0].hasPrefix("╭─ PureMac "))
        XCTAssertTrue(lines[0].hasSuffix("─╮"))
        XCTAssertEqual(lines[1], "│ Choose a task" + String(repeating: " ", count: 24) + "│")
        XCTAssertTrue(lines[3].hasPrefix("│ › 1.  Tool 1"))
        XCTAssertTrue(lines[4].hasPrefix("│       Description 1"))
        XCTAssertTrue(lines[5].hasPrefix("│   2.  Tool 2"))
        XCTAssertTrue(lines[8].hasPrefix("├"))
        XCTAssertTrue(lines[8].hasSuffix("┤"))
        XCTAssertTrue(lines[11].hasPrefix("╰"))
        XCTAssertFalse(lines.contains { $0.contains("PUREMAC") })
    }

    func testMenuRenderStylesFocusedRowAndDimsOthers() {
        let colored = renderMenu(options: menuOptions(2), selection: 0, width: 40, height: 12)
            .lines(colors: true)
        XCTAssertTrue(colored[3].contains("\u{1B}[7m"))
        XCTAssertTrue(colored[3].contains("\u{1B}[7;36m›"))
        XCTAssertFalse(colored[5].contains("\u{1B}[7"))
        XCTAssertTrue(colored[6].contains("\u{1B}[2mDescription 2"))
        XCTAssertFalse(colored[4].contains("\u{1B}[2mDescription 1"))
    }

    func testMenuRenderShowsScrollbarOnlyWhenOptionsDoNotFit() {
        let overflowing = renderMenu(options: menuOptions(8), selection: 0, width: 40, height: 12).plainLines()
        XCTAssertTrue(overflowing.contains { $0.hasSuffix("┃") })
        let fitting = renderMenu(options: menuOptions(2), selection: 0, width: 40, height: 12).plainLines()
        XCTAssertFalse(fitting.contains { $0.contains("┃") })
    }

    func testMenuRenderTruncatesLongSubtitleWithEllipsis() {
        let buffer = TerminalMenu.render(
            title: "PureMac",
            subtitle: "Your Mac, with room to work.  /  1.1.1",
            options: menuOptions(2),
            selection: 0,
            width: 40,
            height: 12
        )
        XCTAssertTrue(buffer.plainLines()[1].hasSuffix("…" + " │"))
    }

    func testMenuRenderFocusedRowInverseCoversContentWidthAndDetailIsPlain() {
        let buffer = renderMenu(options: menuOptions(2), selection: 0, width: 40, height: 12)
        XCTAssertTrue(buffer[37, 3].style.inverse)
        XCTAssertFalse(buffer[1, 3].style.inverse)
        XCTAssertEqual(buffer[8, 4].style, .plain)
        XCTAssertEqual(buffer[2, 1].style, TextStyle(dim: true))
    }

    func testMenuRenderBelowMinimumUsesTooSmallScreen() {
        let buffer = renderMenu(options: menuOptions(2), selection: 0, width: 30, height: 8)
        XCTAssertEqual(buffer, TooSmallScreen.render(title: "PureMac", exitHint: "Esc/q cancel", width: 30, height: 8))
    }

    func testTooSmallScreenFitsAtMinimumOnly() {
        XCTAssertTrue(TooSmallScreen.fits(width: 40, height: 12))
        XCTAssertFalse(TooSmallScreen.fits(width: 39, height: 12))
        XCTAssertFalse(TooSmallScreen.fits(width: 40, height: 11))
    }

    func testTooSmallScreenRendersCopyTruncatedAndLimited() {
        let lines = TooSmallScreen.render(title: "PureMac", exitHint: "Esc/q cancel", width: 18, height: 4).plainLines()
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == 18 })
        XCTAssertTrue(lines[0].hasPrefix("PureMac"))
        XCTAssertTrue(lines[1].hasPrefix("Terminal too small"))
        XCTAssertTrue(lines[2].hasPrefix("Resize to at lea"))
        XCTAssertEqual(lines[3].trimmingCharacters(in: .whitespaces), "")

        let tall = TooSmallScreen.render(title: "PureMac", exitHint: "Esc/q cancel", width: 30, height: 6).plainLines()
        XCTAssertTrue(tall[2].hasPrefix("Resize to at least 40 x 12"))
        XCTAssertTrue(tall[4].hasPrefix("Esc/q cancel"))

        let colored = TooSmallScreen.render(title: "PureMac", exitHint: "Esc/q cancel", width: 30, height: 6)
            .lines(colors: true)
        XCTAssertTrue(colored[0].contains("\u{1B}[1;36mPureMac"))
        XCTAssertTrue(colored[2].contains("\u{1B}[2mResize"))
    }

    func testFocusPointerShowsCyanInverseArrowOnlyWhenFocused() {
        XCTAssertEqual(FocusPointer.span(focused: true), Span("›", TextStyle(color: .cyan, inverse: true)))
        XCTAssertEqual(FocusPointer.span(focused: false), Span(" "))
    }

    func testSizeColumnWidthIsSharedWithPlainOutput() {
        XCTAssertEqual(Term.displayWidth(Render.sizeCol(1_024)), Render.sizeColumnWidth)
    }

    private func menuOptions(_ count: Int) -> [(title: String, detail: String)] {
        (1...count).map { (title: "Tool \($0)", detail: "Description \($0)") }
    }

    private func renderMenu(
        options: [(title: String, detail: String)],
        selection: Int,
        width: Int,
        height: Int
    ) -> Buffer {
        TerminalMenu.render(
            title: "PureMac",
            subtitle: "Choose a task",
            options: options,
            selection: selection,
            width: width,
            height: height
        )
    }

    private func renderReview(_ model: InteractiveReviewModel, width: Int, height: Int) -> Buffer {
        InteractiveReview.render(model: model, title: "Review removable files", width: width, height: height)
    }

    private func manyItemsCategories(_ count: Int) -> [CategoryScan] {
        [
            CategoryScan(
                id: "many",
                title: "Many",
                groups: [
                    ToolGroup(
                        tool: "Items",
                        items: (0..<count).map { ScanItem(path: "/tmp/item\($0)", sizeBytes: 1_000, modified: nil) }
                    )
                ]
            )
        ]
    }

    private func fixtureCategories() -> [CategoryScan] {
        [
            CategoryScan(
                id: "dev",
                title: "Developer",
                groups: [
                    ToolGroup(
                        tool: "Build caches",
                        items: [
                            ScanItem(path: "/tmp/first", sizeBytes: 1_000, modified: nil, selected: true),
                            ScanItem(path: "/tmp/second", sizeBytes: 2_000, modified: nil, selected: true)
                        ]
                    ),
                    ToolGroup(
                        tool: "Package caches",
                        items: [
                            ScanItem(path: "/tmp/third", sizeBytes: 3_000, modified: nil, selected: false)
                        ]
                    )
                ]
            )
        ]
    }
}

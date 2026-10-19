import ArgumentParser
import XCTest
@testable import puremac
import TerminalUI

final class CleanupFlowTests: XCTestCase {
    private let labels = CleanupFlow.Labels(
        scanning: "Scanning Developer caches …",
        empty: "No cleanup candidates found in readable locations.",
        reviewTitle: "Choose items to clean",
        noun: "item"
    )

    func testScanningScreenUsesPureMacTitleMessageAndCancelHint() {
        let lines = CleanupFlow.scanningScreen(labels: labels, width: 60, height: 14).plainLines()
        XCTAssertTrue(lines[0].hasPrefix("╭─ PureMac "))
        XCTAssertTrue(lines[1].contains("Scanning Developer caches …"))
        XCTAssertTrue(lines.contains { $0.contains("Ctrl+C cancel") })
    }

    func testEmptyScreenShowsInfoDialogOverFadedScanningScreen() {
        let buffer = CleanupFlow.emptyScreen(labels: labels, width: 80, height: 24)
        let lines = buffer.plainLines()
        XCTAssertTrue(lines.contains { $0.contains("Nothing to clean") })
        XCTAssertTrue(lines.contains { $0.contains("No cleanup candidates found in readable locations.") })
        XCTAssertTrue(lines.contains { $0.contains("› OK ‹") })
        XCTAssertTrue(lines.contains { $0.contains("Scanning Developer caches …") })
        XCTAssertEqual(buffer[0, 0].style, TextStyle(dim: true))
        XCTAssertTrue(buffer.lines(colors: true).joined().contains("\u{1B}[7m› OK ‹"))
    }

    func testEmptyScreenClosesOnEnterEscapeAndQOnly() {
        XCTAssertTrue(CleanupFlow.closesInfoDialog(.enter))
        XCTAssertTrue(CleanupFlow.closesInfoDialog(.escape))
        XCTAssertTrue(CleanupFlow.closesInfoDialog(.character("q")))
        XCTAssertTrue(CleanupFlow.closesInfoDialog(.character("Q")))
        XCTAssertFalse(CleanupFlow.closesInfoDialog(.space))
        XCTAssertFalse(CleanupFlow.closesInfoDialog(.character("y")))
        XCTAssertFalse(CleanupFlow.closesInfoDialog(.up))
    }

    func testRemovingScreenShowsStatusDialogWithoutButtonsOverFadedSelectionScreen() {
        let buffer = CleanupFlow.removingScreen(
            review: review(), labels: labels, progress: progress(), tick: 0, width: 80, height: 24
        )
        let lines = buffer.plainLines()
        XCTAssertTrue(lines.contains { $0.contains("Removing 2 items…") })
        XCTAssertTrue(lines.contains { $0.contains("⠋ /tmp/second") })
        XCTAssertTrue(lines.contains { $0.contains("2 of 2") })
        let dialog = CleanupFlow.removingDialog(noun: "item", progress: progress(), tick: 0, area: buffer.area)
        XCTAssertTrue(dialog.buttons.isEmpty)
        XCTAssertNil(dialog.focusedButton)
        XCTAssertNil(dialog.hints)
        XCTAssertTrue(lines.contains { $0.contains("╭─ Choose items to clean ") })
        XCTAssertFalse(lines.contains { $0.contains("Final review") })
        XCTAssertTrue(lines.contains { $0.contains("/tmp/first") })
        XCTAssertTrue(lines.contains { $0.contains("/tmp/third") })
        XCTAssertEqual(buffer[0, 0].style, TextStyle(dim: true))
        let frame = dialog.frame(in: buffer.area)
        XCTAssertEqual(buffer[frame.x, frame.y].style, TextStyle(color: .yellow))
        XCTAssertEqual(buffer[frame.x + 3, frame.y].style, TextStyle(color: .yellow, bold: true))
    }

    func testRemovingDialogShowsSpinnerFrameForTheTick() {
        let area = Rect(x: 0, y: 0, width: 80, height: 24)
        let first = CleanupFlow.removingDialog(noun: "item", progress: progress(), tick: 0, area: area)
        let second = CleanupFlow.removingDialog(noun: "item", progress: progress(), tick: 1, area: area)
        XCTAssertTrue(first.message[0].text.hasPrefix("\(Spinner.frame(tick: 0)) "))
        XCTAssertTrue(second.message[0].text.hasPrefix("\(Spinner.frame(tick: 1)) "))
    }

    func testRemovingDialogCountRowIsDim() {
        let dialog = CleanupFlow.removingDialog(
            noun: "item", progress: RemovalProgress(index: 2, count: 5, path: "/tmp/a"), tick: 0,
            area: Rect(x: 0, y: 0, width: 80, height: 24)
        )
        XCTAssertEqual(dialog.message[1], Span("3 of 5", TextStyle(dim: true)))
        XCTAssertEqual(dialog.message.count, 2)
    }

    func testRemovingDialogKeepsRowsInTheFirstContentColumn() {
        let area = Rect(x: 0, y: 0, width: 80, height: 24)
        let dialog = CleanupFlow.removingDialog(noun: "item", progress: progress(), tick: 0, area: area)
        var buffer = Buffer(width: 80, height: 24)
        dialog.render(in: area, buffer: &buffer)
        let frame = dialog.frame(in: area)
        let lines = buffer.plainLines()
        let spinnerRow = lines.first { $0.contains("⠋ /tmp/second") }!
        let countRow = lines.first { $0.contains("2 of 2") }!
        let spinnerColumn = spinnerRow.distance(from: spinnerRow.startIndex, to: spinnerRow.range(of: "⠋")!.lowerBound)
        let countColumn = countRow.distance(from: countRow.startIndex, to: countRow.range(of: "2 of 2")!.lowerBound)
        XCTAssertEqual(spinnerColumn, frame.x + 3)
        XCTAssertEqual(countColumn, frame.x + 3)
    }

    func testRemovingDialogKeepsFixedWidthAcrossItems() {
        let wide = Rect(x: 0, y: 0, width: 120, height: 24)
        let short = RemovalProgress(index: 0, count: 2, path: "/tmp/a")
        let long = RemovalProgress(index: 1, count: 2, path: "/tmp/" + String(repeating: "deep-name/", count: 20))
        let shortDialog = CleanupFlow.removingDialog(noun: "item", progress: short, tick: 0, area: wide)
        let longDialog = CleanupFlow.removingDialog(noun: "item", progress: long, tick: 5, area: wide)
        XCTAssertEqual(shortDialog.frame(in: wide), longDialog.frame(in: wide))
        XCTAssertEqual(shortDialog.frame(in: wide).width, 60 + 6)
        let narrow = Rect(x: 0, y: 0, width: 40, height: 12)
        XCTAssertEqual(
            CleanupFlow.removingDialog(noun: "item", progress: short, tick: 0, area: narrow).frame(in: narrow).width,
            Dialog.maxContentWidth(in: narrow) + 6
        )
    }

    func testRemovingDialogShortensAndMiddleTruncatesThePath() {
        let area = Rect(x: 0, y: 0, width: 80, height: 24)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = home + "/Library/Caches/" + String(repeating: "very-long-name/", count: 8) + "end"
        let row = CleanupFlow.removingDialog(
            noun: "item", progress: RemovalProgress(index: 0, count: 1, path: path), tick: 0, area: area
        ).message[0].text
        XCTAssertEqual(Term.displayWidth(row), 60)
        XCTAssertTrue(row.contains("~/Library"))
        XCTAssertTrue(row.contains("…"))
        XCTAssertTrue(row.hasSuffix("end"))
    }

    func testRemovalProgressIsOneBasedAndSizedFromTheCleanerCallback() {
        let progress = RemovalProgress(index: 0, count: 3, path: "/tmp/x")
        XCTAssertEqual(progress.position, 1)
        XCTAssertEqual(progress.count, 3)
        XCTAssertEqual(RemovalProgress(index: 2, count: 3, path: "/tmp/y").position, 3)
    }

    func testRemovingTitleUsesSingularForOneItem() {
        let area = Rect(x: 0, y: 0, width: 80, height: 24)
        func title(_ count: Int, _ noun: String) -> String {
            CleanupFlow.removingDialog(
                noun: noun, progress: RemovalProgress(index: 0, count: count, path: "/tmp/a"), tick: 0, area: area
            ).title
        }
        XCTAssertEqual(title(1, "item"), "Removing 1 item…")
        XCTAssertEqual(title(1, "artifact"), "Removing 1 artifact…")
        XCTAssertEqual(title(0, "item"), "Removing 0 items…")
        XCTAssertEqual(title(2, "artifact"), "Removing 2 artifacts…")
    }

    func testRemovingDialogUsesTheNoun() {
        let lines = CleanupFlow.removingScreen(
            review: review(),
            labels: CleanupFlow.Labels(scanning: "s", empty: "e", reviewTitle: "t", noun: "artifact"),
            progress: progress(), tick: 0, width: 80, height: 24
        ).plainLines()
        XCTAssertTrue(lines.contains { $0.contains("Removing 2 artifacts…") })
    }

    func testResultScreenShowsSummaryRowsAndFocusedDoneButton() {
        let outcome = CleanOutcome(removed: 2, freedBytes: 1_500, skipped: [], failed: [])
        let buffer = CleanupFlow.resultScreen(outcome: outcome, review: review(), labels: labels, width: 80, height: 24)
        let lines = buffer.plainLines()
        XCTAssertTrue(lines.contains { $0.contains("Cleanup complete") })
        XCTAssertTrue(lines.contains { $0.contains("1.5 KB removed across 2 items") })
        XCTAssertFalse(lines.contains { $0.contains("skipped") })
        XCTAssertFalse(lines.contains { $0.contains("failed") })
        XCTAssertTrue(lines.contains { $0.contains("› Done ‹") })
        XCTAssertTrue(lines.contains { $0.contains("/tmp/first") })
        let colored = buffer.lines(colors: true).joined()
        XCTAssertTrue(colored.contains("\u{1B}[1;32mCleanup complete"))
        XCTAssertTrue(colored.contains("\u{1B}[7m› Done ‹"))
    }

    func testResultDialogSingularItemAndSkippedRow() {
        let outcome = CleanOutcome(removed: 1, freedBytes: 1_000, skipped: [(path: "/tmp/a", reason: "symlink")], failed: [])
        let lines = CleanupFlow.resultScreen(outcome: outcome, review: review(), labels: labels, width: 80, height: 24)
        XCTAssertTrue(lines.plainLines().contains { $0.contains("1 KB removed across 1 item ") })
        XCTAssertTrue(lines.plainLines().contains { $0.contains("1 skipped  protected or ignored") })
        XCTAssertTrue(lines.lines(colors: true).joined().contains("\u{1B}[33m1 skipped  protected or ignored"))
    }

    func testResultDialogListsFailureCountAndUpToThreePaths() {
        let failures = (1...4).map { (path: "/tmp/fail\($0)", error: "denied") }
        let outcome = CleanOutcome(removed: 0, freedBytes: 0, skipped: [], failed: failures)
        let buffer = CleanupFlow.resultScreen(outcome: outcome, review: review(), labels: labels, width: 80, height: 24)
        let lines = buffer.plainLines()
        XCTAssertTrue(lines.contains { $0.contains("4 failed") })
        XCTAssertTrue(lines.contains { $0.contains("! /tmp/fail1") })
        XCTAssertTrue(lines.contains { $0.contains("! /tmp/fail3") })
        XCTAssertFalse(lines.contains { $0.contains("fail4") })
        let colored = buffer.lines(colors: true).joined()
        XCTAssertTrue(colored.contains("\u{1B}[31m4 failed"))
        XCTAssertTrue(colored.contains("\u{1B}[31m! /tmp/fail1"))
    }

    func testResultScreenFitsMinimumSize() {
        let failures = (1...4).map { (path: "/tmp/fail\($0)", error: "denied") }
        let outcome = CleanOutcome(removed: 3, freedBytes: 5_000, skipped: [(path: "/tmp/a", reason: "x")], failed: failures)
        let lines = CleanupFlow.resultScreen(outcome: outcome, review: review(), labels: labels, width: 40, height: 12)
            .plainLines()
        XCTAssertEqual(lines.count, 12)
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == 40 })
        XCTAssertTrue(lines.contains { $0.contains("› Done ‹") })
    }

    func testOutcomeTextIsSharedWithTheTerminalSummary() {
        let outcome = CleanOutcome(removed: 2, freedBytes: 1_500, skipped: [(path: "/a", reason: "x")], failed: [(path: "/b", error: "y")])
        XCTAssertEqual(Render.removedDetail(outcome), " removed across 2 items")
        XCTAssertEqual(Render.removedDetail(CleanOutcome(removed: 1)), " removed across 1 item")
        XCTAssertEqual(Render.skippedLabel(outcome), "1 skipped")
        XCTAssertEqual(Render.skippedNote, "  protected or ignored")
        XCTAssertEqual(Render.failedLabel(outcome), "1 failed")
    }

    func testFinishPrintsTheCopyForEachResultAndKeepsExitStatus() throws {
        XCTAssertEqual(
            try captureStdout { try CleanupFlow.finish(.nothingFound, labels: labels) },
            "No cleanup candidates found in readable locations.\n"
        )
        XCTAssertEqual(
            try captureStdout { try CleanupFlow.finish(.cancelled, labels: labels) },
            "Cancelled. Nothing removed.\n"
        )
        XCTAssertEqual(
            try captureStdout { try CleanupFlow.finish(.finished(CleanOutcome(removed: 1, freedBytes: 10)), labels: labels) },
            "\nCleanup complete\n10 bytes removed across 1 item\n\n"
        )
        let failed = CleanOutcome(failed: [(path: "/x", error: "e")])
        var thrown: Error?
        let printed = try captureStdout {
            do { try CleanupFlow.finish(.finished(failed), labels: labels) } catch { thrown = error }
        }
        XCTAssertEqual(thrown as? ExitCode, ExitCode.failure)
        XCTAssertTrue(printed.contains("1 failed"))
        let skipped = CleanOutcome(skipped: [(path: "/x", reason: "r")])
        var skippedError: Error?
        let skippedPrinted = try captureStdout {
            do { try CleanupFlow.finish(.finished(skipped), labels: labels) } catch { skippedError = error }
        }
        XCTAssertEqual(skippedError as? ExitCode, ExitCode.failure)
        XCTAssertTrue(skippedPrinted.contains("1 skipped  protected or ignored"))
    }

    func testLongFailurePathsStayOnOneRowEach() {
        let long = "/Users/someone/Library/Developer/Xcode/DerivedData/" + String(repeating: "very-long-name/", count: 6)
        let failures = (1...3).map { (path: long + "f\($0)", error: "denied") }
        let outcome = CleanOutcome(removed: 0, freedBytes: 0, skipped: [], failed: failures)
        for (width, height) in [(40, 12), (80, 24)] {
            let buffer = CleanupFlow.resultScreen(outcome: outcome, review: review(), labels: labels, width: width, height: height)
            let lines = buffer.plainLines()
            XCTAssertEqual(lines.filter { $0.contains("! ") }.count, 3, "\(width)x\(height)")
            XCTAssertFalse(lines.contains { $0.contains("!") && !$0.contains("! ") }, "\(width)x\(height)")
            XCTAssertTrue(lines.contains { $0.contains("› Done ‹") })
        }
    }

    func testTooSmallInfoScreensShowTheKeyThatClosesThem() {
        let empty = CleanupFlow.emptyScreen(labels: labels, width: 30, height: 8).plainLines()
        XCTAssertTrue(empty.contains { $0.contains("Enter close") })
        XCTAssertFalse(empty.contains { $0.contains("Ctrl+C") })
        let outcome = CleanOutcome(removed: 1, freedBytes: 1_000)
        let result = CleanupFlow.resultScreen(outcome: outcome, review: review(), labels: labels, width: 30, height: 8).plainLines()
        XCTAssertTrue(result.contains { $0.contains("Enter close") })
        XCTAssertFalse(result.contains { $0.contains("cancel") })
    }

    func testTooSmallRemovingScreenMakesNoCancelPromise() {
        let lines = CleanupFlow.removingScreen(
            review: review(), labels: labels, progress: progress(), tick: 0, width: 30, height: 8
        ).plainLines()
        XCTAssertTrue(lines.contains { $0.contains("Removing") })
        XCTAssertFalse(lines.contains { $0.contains("Esc") || $0.contains("cancel") })
    }

    func testBackgroundKeepsTheSelectionFilter() {
        let model = InteractiveReviewModel.selected(selection(), selecting: [0], query: "first")
        let lines = CleanupFlow.resultScreen(
            outcome: CleanOutcome(removed: 1, freedBytes: 1_000), review: model, labels: labels, width: 80, height: 24
        ).plainLines()
        XCTAssertTrue(lines.contains { $0.contains("Filter  first") })
    }

    private func progress() -> RemovalProgress {
        RemovalProgress(index: 1, count: 2, path: "/tmp/second")
    }

    private func review() -> InteractiveReviewModel {
        .selected(selection(), selecting: [0, 1])
    }

    private func selection() -> [CategoryScan] {
        [
            CategoryScan(
                id: "dev",
                title: "Developer",
                groups: [
                    ToolGroup(
                        tool: "Build caches",
                        items: [
                            ScanItem(path: "/tmp/first", sizeBytes: 1_000, modified: nil, selected: true),
                            ScanItem(path: "/tmp/second", sizeBytes: 2_000, modified: nil, selected: true),
                            ScanItem(path: "/tmp/third", sizeBytes: 3_000, modified: nil, selected: false)
                        ]
                    )
                ]
            )
        ]
    }
}

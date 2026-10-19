import XCTest
@testable import puremac
import TerminalUI

final class InfoSheetTests: XCTestCase {
    private let dim = TextStyle(dim: true)

    private func sample(extraRows: Int = 0) -> InfoSheet {
        InfoSheet(
            title: "Mac status",
            subtitle: "Read-only measurements",
            sections: [
                InfoSection(title: "Memory", rows: [
                    .gauge(fraction: 0.5, color: .green, text: "8 GB in use of 16 GB"),
                    .metric(label: "Pressure", value: [Span("Normal", TextStyle(color: .green))], note: nil),
                    .metric(label: "Installed", value: [Span("16 GB")], note: Span("saved", dim)),
                ] + (0..<extraRows).map { .message([Span("extra \($0)")]) }),
                InfoSection(title: nil, rows: [.message([Span("Uptime", dim), Span("  1h 1m")])]),
            ],
            footnote: "Nothing ran."
        )
    }

    func testPlainLinesWithoutColorsKeepTheCommandLayout() {
        XCTAssertEqual(sample().plainLines(colors: false), [
            "Mac status",
            "Read-only measurements",
            "",
            "Memory",
            "  ██████████░░░░░░░░░░ 8 GB in use of 16 GB",
            "  Pressure          Normal",
            "  Installed         16 GB  saved",
            "",
            "  Uptime  1h 1m",
            "",
            "Nothing ran.",
        ])
    }

    func testPlainLinesCanSkipTheHeader() {
        XCTAssertEqual(sample().plainLines(withHeader: false, colors: false).first, "Memory")
    }

    func testPlainLinesWithColorsStyleHeadingsLabelsAndGauge() {
        let lines = sample().plainLines(colors: true)
        XCTAssertEqual(lines[0], "\u{1B}[0m\u{1B}[1mMac status\u{1B}[0m")
        XCTAssertEqual(lines[1], "\u{1B}[0m\u{1B}[2mRead-only measurements\u{1B}[0m")
        XCTAssertTrue(lines[4].contains("\u{1B}[0m\u{1B}[32m██████████\u{1B}[0m\u{1B}[2m░░░░░░░░░░"), lines[4])
        XCTAssertTrue(lines[5].contains("\u{1B}[2mPressure"), lines[5])
        XCTAssertTrue(lines[5].contains("\u{1B}[32mNormal"), lines[5])
        XCTAssertTrue(lines[6].contains("\u{1B}[2msaved"), lines[6])
        XCTAssertEqual(lines.last, "\u{1B}[0m\u{1B}[2mNothing ran.\u{1B}[0m")
    }

    func testGaugeWithoutColorKeepsTheFilledPartPlain() {
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, rows: [.gauge(fraction: 0.5, color: nil, text: "x")])],
            footnote: nil
        )
        XCTAssertEqual(
            sheet.plainLines(withHeader: false, colors: true),
            ["  ██████████\u{1B}[0m\u{1B}[2m░░░░░░░░░░\u{1B}[0m x"]
        )
    }

    func testWindowShowsTitleSubtitleRowsAndHints() {
        let buffer = sample().render(width: 60, height: 20, offset: 0)
        let lines = buffer.plainLines()
        XCTAssertEqual(lines.count, 20)
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == 60 })
        XCTAssertTrue(lines[0].hasPrefix("╭─ Mac status "))
        XCTAssertTrue(lines[1].contains("Read-only measurements"))
        XCTAssertEqual(buffer[2, 1].style, dim)
        XCTAssertTrue(lines.contains { $0.contains("Memory") })
        XCTAssertTrue(lines.contains { $0.contains("██████████░░░░░░░░░░ 8 GB in use of 16 GB") })
        XCTAssertTrue(lines.contains { $0.contains("Nothing ran.") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("├") && $0.hasSuffix("┤") })
        XCTAssertTrue(lines.contains { $0.contains("↑↓ scroll") && $0.contains("Esc back") })
        XCTAssertFalse(lines.contains { $0.contains("┃") })
    }

    func testWindowScrollsAndShowsAScrollbarWhenRowsDoNotFit() {
        let sheet = sample(extraRows: 30)
        let top = sheet.render(width: 60, height: 14, offset: 0)
        XCTAssertTrue(top.plainLines().contains { $0.contains("┃") })
        XCTAssertTrue(top.plainLines().contains { $0.contains("Read-only measurements") })
        let scrolled = sheet.render(width: 60, height: 14, offset: 5)
        XCTAssertFalse(scrolled.plainLines().contains { $0.contains("Read-only measurements") })
        let bottom = sheet.render(width: 60, height: 14, offset: 10_000)
        XCTAssertTrue(bottom.plainLines().contains { $0.contains("Nothing ran.") })
    }

    func testWindowTruncatesLongMetricRows() {
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, rows: [.metric(label: "Path", value: [Span(String(repeating: "a", count: 60))], note: nil)])],
            footnote: nil
        )
        let lines = sheet.render(width: 40, height: 12, offset: 0).plainLines()
        XCTAssertTrue(lines.contains { $0.contains("…") })
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == 40 })
    }

    func testWindowWrapsMessageRowsWithSeveralSpansKeepingStyles() {
        let cyan = TextStyle(color: .cyan)
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, rows: [
                .message([Span("No protected paths. Add one with ", dim), Span("`puremac ignore add <path>`", cyan), Span(".", dim)])
            ])],
            footnote: nil
        )
        let buffer = sheet.render(width: 40, height: 12, offset: 0)
        let lines = buffer.plainLines()
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == 40 })
        XCTAssertFalse(lines.contains { $0.contains("…") })
        let text = lines.joined(separator: " ")
        for word in ["protected", "puremac", "ignore", "add", "<path>`."] { XCTAssertTrue(text.contains(word), word) }
        let intro = lines.firstIndex { $0.contains("Add one with") }
        let command = lines.firstIndex { $0.contains("puremac") }
        XCTAssertNotNil(intro)
        XCTAssertNotEqual(intro, command, "the hint wraps onto a second row")
        let row = command ?? 0
        let styled = (0..<40).filter { buffer[$0, row].style == cyan }.map { buffer[$0, row].symbol }.joined()
        XCTAssertEqual(styled, "`puremac ignore add <path>`")
        XCTAssertEqual(buffer[4, intro ?? 0].style, dim)
        XCTAssertTrue(lines[row].hasPrefix("│   `"), lines[row])
    }

    func testWindowGaugeShrinksItsBarSoTheWholeTextFitsAt40Columns() {
        let text = "107.4 GB free of 536.9 GB"
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, rows: [.gauge(fraction: 0.8, color: .green, text: text)])],
            footnote: nil
        )
        let narrow = sheet.render(width: 40, height: 12, offset: 0).plainLines()
        let row = narrow.first { $0.contains("█") }
        XCTAssertNotNil(row)
        XCTAssertTrue(row?.contains(text) == true, row ?? "")
        XCTAssertFalse(narrow.contains { $0.contains("…") })
        let wide = sheet.render(width: 80, height: 12, offset: 0).plainLines()
        let bar = wide.first { $0.contains("█") }?.filter { "█░".contains($0) }.count
        XCTAssertEqual(bar, 20)
    }

    func testWindowGaugeWithoutRoomForABarShowsOnlyItsText() {
        let text = String(repeating: "y", count: 33)
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, rows: [.gauge(fraction: 0.5, color: .green, text: text)])],
            footnote: nil
        )
        let lines = sheet.render(width: 40, height: 12, offset: 0).plainLines()
        let row = lines.first { $0.contains(text) }
        XCTAssertNotNil(row)
        XCTAssertTrue(row?.hasPrefix("│   " + text) == true, row ?? "")
        XCTAssertFalse(lines.contains { $0.contains("█") || $0.contains("░") || $0.contains("…") })
    }

    func testWindowShowsALongPathRowAsOneMiddleTruncatedRow() {
        let path = "/Users/x/Projects/some/deep/folder/name-0"
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, rows: [.path(path), .path("/tmp/short")])],
            footnote: nil
        )
        let lines = sheet.render(width: 40, height: 12, offset: 0).plainLines()
        let rows = lines.filter { $0.contains("/Users") || $0.contains("name-0") }
        XCTAssertEqual(rows.count, 1, "\(rows)")
        XCTAssertTrue(rows[0].contains("…") && rows[0].contains("name-0"), rows[0])
        XCTAssertTrue(rows[0].hasPrefix("│   /Users"), rows[0])
        XCTAssertTrue(lines.contains { $0.hasPrefix("│   /tmp/short ") })
    }

    func testPlainLinesShowAPathRowWithTwoSpacesAndNoTruncation() {
        let path = "/Users/x/Projects/some/deep/folder/name-0"
        let sheet = InfoSheet(title: "T", subtitle: nil, sections: [InfoSection(title: nil, rows: [.path(path)])], footnote: nil)
        XCTAssertEqual(sheet.plainLines(withHeader: false, colors: false), ["  " + path])
    }

    func testPlainLinesKeepZeroWidthCharactersInPaths() {
        let sheet = InfoSheet(title: "T", subtitle: nil, sections: [InfoSection(title: nil, rows: [.path("/tmp/a\u{200B}b")])], footnote: nil)
        XCTAssertEqual(sheet.plainLines(withHeader: false, colors: false), ["  /tmp/a\u{200B}b"])
    }

    func testMaxOffsetIsZeroWhenEverythingFitsOrTheScreenIsTooSmall() {
        XCTAssertEqual(sample().maxOffset(width: 60, height: 30), 0)
        XCTAssertEqual(sample(extraRows: 30).maxOffset(width: 39, height: 11), 0)
    }

    func testMaxOffsetIsTheLargestOffsetThatStillMovesTheWindow() {
        let sheet = sample(extraRows: 30)
        let most = sheet.maxOffset(width: 60, height: 14)
        XCTAssertGreaterThan(most, 0)
        XCTAssertEqual(sheet.render(width: 60, height: 14, offset: most), sheet.render(width: 60, height: 14, offset: most + 5))
        XCTAssertNotEqual(sheet.render(width: 60, height: 14, offset: most - 1), sheet.render(width: 60, height: 14, offset: most))
    }

    func testMaxOffsetCountsWrappedRows() {
        let long = InfoSheet(title: "T", subtitle: nil, sections: [InfoSection(title: nil, rows: [.message([Span(Array(repeating: "word", count: 80).joined(separator: " "))])])], footnote: nil)
        XCTAssertGreaterThan(long.maxOffset(width: 40, height: 12), long.maxOffset(width: 100, height: 12))
    }

    func testSectionLabelWidthPadsPlainLabels() {
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, labelWidth: 8, rows: [.metric(label: "Name", value: [Span("x")], note: nil)])],
            footnote: nil
        )
        XCTAssertEqual(sheet.plainLines(withHeader: false, colors: false), ["  Name     x"])
    }

    func testWindowMovesAMetricValueAndNoteToASecondRowWhenTheRowIsTooWide() {
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, labelWidth: 26, rows: [
                .metric(label: "purge.older_than_days", value: [Span("7 days")], note: Span("default", dim)),
                .metric(label: "Short", value: [Span("x")], note: nil),
            ])],
            footnote: nil
        )
        let lines = sheet.render(width: 40, height: 12, offset: 0).plainLines()
        let label = lines.firstIndex { $0.contains("purge.older_than_days") }
        XCTAssertNotNil(label)
        XCTAssertFalse(lines[label ?? 0].contains("…"))
        XCTAssertTrue(lines[(label ?? 0) + 1].hasPrefix("│     7 days  default"), lines[(label ?? 0) + 1])
        XCTAssertTrue(lines.contains { $0.hasPrefix("│   Short") && $0.contains(" x") }, "a row that fits stays on one line")
        let wide = sheet.render(width: 80, height: 12, offset: 0).plainLines()
        XCTAssertTrue(wide.contains { $0.contains("purge.older_than_days") && $0.contains("7 days  default") })
    }

    func testWindowMiddleTruncatesALongMetricValueOnItsSecondRow() {
        let path = "/Users/someone/.config/puremac/deep/config.json"
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, labelWidth: 12, rows: [.metric(label: "Settings", value: [Span(path)], note: nil)])],
            footnote: nil
        )
        let lines = sheet.render(width: 40, height: 12, offset: 0).plainLines()
        let row = lines.first { $0.contains("config.json") }
        XCTAssertNotNil(row)
        XCTAssertTrue(row?.hasPrefix("│     /Users") == true && row?.contains("…") == true, row ?? "")
        XCTAssertTrue(lines.contains { $0.contains("Settings") })
        XCTAssertEqual(sheet.plainLines(withHeader: false, colors: false), ["  Settings     " + path])
    }

    func testLoadingReturnsTheSheetOrARedErrorRow() {
        struct Failure: LocalizedError { var errorDescription: String? { "disk unavailable" } }
        let ok = InfoSheet(title: "T", subtitle: nil, sections: [], footnote: nil)
        XCTAssertEqual(InfoSheet.loading(title: "Fallback") { ok }.title, "T")
        let failed = InfoSheet.loading(title: "Mac status") { throw Failure() }
        XCTAssertEqual(failed.title, "Mac status")
        XCTAssertEqual(failed.sections.count, 1)
        guard case .message(let spans) = failed.sections[0].rows[0] else { return XCTFail("message row") }
        XCTAssertEqual(spans, [Span("disk unavailable", TextStyle(color: .red))])
    }

    func testWindowWrapsLongMessagesAndFootnoteInsteadOfCutting() {
        let note = "Managed capacity may include purgeable files and is not guaranteed free space."
        let footnote = "No maintenance ran. Use `puremac clean --dry-run` to review removable files."
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, rows: [.message([Span(note, dim)])])],
            footnote: footnote
        )
        for width in [80, 50] {
            let lines = sheet.render(width: width, height: 20, offset: 0).plainLines()
            XCTAssertFalse(lines.contains { $0.contains("…") }, "\(width)")
            XCTAssertTrue(lines.contains { $0.contains("space.") }, "\(width)")
            XCTAssertTrue(lines.contains { $0.contains("--dry-run`") }, "\(width)")
            XCTAssertTrue(lines.contains { $0.contains("removable files.") }, "\(width)")
        }
        let wrapped = sheet.render(width: 50, height: 20, offset: 0).plainLines().filter { $0.contains("purgeable") || $0.contains("guaranteed") }
        XCTAssertTrue(wrapped.allSatisfy { $0.contains("│  ") }, "continuation keeps the row indent")
    }

    func testWindowWrapsLongSubtitle() {
        let subtitle = "Read-only measurements taken from macOS system counters at the moment you opened this view"
        let sheet = InfoSheet(title: "T", subtitle: subtitle, sections: [], footnote: nil)
        let buffer = sheet.render(width: 40, height: 12, offset: 0)
        let lines = buffer.plainLines()
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == 40 })
        let text = lines.joined(separator: " ")
        for word in subtitle.split(separator: " ") { XCTAssertTrue(text.contains(word), String(word)) }
        XCTAssertFalse(text.contains("…"))
    }

    func testBelowMinimumUsesTooSmallScreen() {
        XCTAssertEqual(
            sample().render(width: 39, height: 11, offset: 0),
            TooSmallScreen.render(title: "Mac status", exitHint: "Esc back", width: 39, height: 11)
        )
    }

    func testScrollMovesByOneAndStaysInRange() {
        var scroll = InfoSheetScroll()
        XCTAssertFalse(scroll.handle(.up, maxOffset: 3))
        XCTAssertEqual(scroll.offset, 0)
        for _ in 0..<5 { XCTAssertFalse(scroll.handle(.down, maxOffset: 3)) }
        XCTAssertEqual(scroll.offset, 3)
        XCTAssertFalse(scroll.handle(.up, maxOffset: 3))
        XCTAssertEqual(scroll.offset, 2)
        XCTAssertFalse(scroll.handle(.down, maxOffset: 0))
        XCTAssertEqual(scroll.offset, 0)
    }

    func testScrollClosesOnEscQEnterLeftAndBackspace() {
        for key in [TerminalKey.escape, .enter, .left, .backspace, .character("q"), .character("Q")] {
            var scroll = InfoSheetScroll()
            XCTAssertTrue(scroll.handle(key, maxOffset: 3), "\(key)")
        }
    }

    func testScrollIgnoresOtherKeys() {
        for key in [TerminalKey.right, .tab, .space, .pageDown, .character("x"), .unknown] {
            var scroll = InfoSheetScroll()
            XCTAssertFalse(scroll.handle(key, maxOffset: 3), "\(key)")
            XCTAssertEqual(scroll.offset, 0)
        }
    }
}

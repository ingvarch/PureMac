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
                    .metric(label: "Installed", value: [Span("16 GB")], note: "saved"),
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

    func testWindowTruncatesLongRows() {
        let sheet = InfoSheet(
            title: "T", subtitle: nil,
            sections: [InfoSection(title: nil, rows: [.message([Span(String(repeating: "a", count: 40)), Span(String(repeating: "b", count: 40))])])],
            footnote: nil
        )
        let lines = sheet.render(width: 40, height: 12, offset: 0).plainLines()
        XCTAssertTrue(lines.contains { $0.contains("…") })
        XCTAssertTrue(lines.allSatisfy { Term.displayWidth($0) == 40 })
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
}

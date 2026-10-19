import XCTest
@testable import TerminalUI

final class GaugeTests: XCTestCase {
    private let dim = TextStyle(dim: true)

    func testFilledAndRestSpans() {
        XCTAssertEqual(Gauge(fraction: 0.5).spans(width: 10), [Span("█████"), Span("░░░░░", dim)])
    }

    func testFilledPartTakesGivenStyleAndRestStaysDim() {
        let green = TextStyle(color: .green)
        XCTAssertEqual(Gauge(fraction: 0.5).spans(width: 10, filled: green), [Span("█████", green), Span("░░░░░", dim)])
        XCTAssertEqual(Gauge(fraction: 1).spans(width: 4, filled: green), [Span("████", green)])
        XCTAssertEqual(Gauge(fraction: 0).spans(width: 4, filled: green), [Span("░░░░", dim)])
    }

    func testEmptyAndFullHaveSingleSpan() {
        XCTAssertEqual(Gauge(fraction: 0).spans(width: 4), [Span("░░░░", dim)])
        XCTAssertEqual(Gauge(fraction: 1).spans(width: 4), [Span("████")])
    }

    func testFractionIsClamped() {
        XCTAssertEqual(Gauge(fraction: 2).spans(width: 3), [Span("███")])
        XCTAssertEqual(Gauge(fraction: -1).spans(width: 3), [Span("░░░", dim)])
    }

    func testNonPositiveWidthHasNoSpans() {
        XCTAssertEqual(Gauge(fraction: 0.5).spans(width: 0), [])
        XCTAssertEqual(Gauge(fraction: 0.5).spans(width: -3), [])
    }

    func testRoundingMatchesTermBar() {
        for width in [1, 5, 12, 24] {
            for step in 0...40 {
                let fraction = Double(step) / 40
                let text = Gauge(fraction: fraction).spans(width: width).map(\.text).joined()
                XCTAssertEqual(text, Term.bar(fraction: fraction, width: width))
            }
        }
    }
}

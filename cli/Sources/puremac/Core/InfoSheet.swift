import TerminalUI

struct InfoSheet {
    var title: String
    var subtitle: String?
    var sections: [InfoSection]
    var footnote: String?

    private static let backHint = KeyHint("Esc", "back")
    private static let hints = KeyHints([KeyHint("↑↓", "scroll"), backHint])
    private static let labelWidth = 17
    private static let gaugeWidth = 20

    func plainLines(withHeader: Bool = true, colors: Bool = Term.colorEnabled) -> [String] {
        var lines: [[Span]] = []
        if withHeader {
            lines.append([Span(title, TextStyle(bold: true))])
            if let subtitle { lines.append([Span(subtitle, TextStyle(dim: true))]) }
            lines.append([])
        }
        return (lines + bodyLines()).map { Self.line($0, colors: colors) }
    }

    func render(width: Int, height: Int, offset: Int) -> Buffer {
        guard TooSmallScreen.fits(width: width, height: height) else {
            return TooSmallScreen.render(title: title, exitHint: "\(Self.backHint.key) \(Self.backHint.action)", width: width, height: height)
        }
        var buffer = Buffer(width: width, height: height)
        let window = Window(title: title)
        let content = window.render(in: buffer.area, buffer: &buffer)
        let areas = content.splitRows([.fill, .length(1), .length(Self.hints.rows(width: content.width).count)])
        let (list, divider, footer) = (areas[0], areas[1], areas[2])

        var lines = bodyLines(wrappingTo: list.width)
        if let subtitle { lines = Self.wrapped(subtitle, style: TextStyle(dim: true), indent: "", width: list.width) + [[]] + lines }
        let start = max(0, min(offset, lines.count - list.height))
        for (index, spans) in lines.dropFirst(start).prefix(list.height).enumerated() {
            Self.write(spans, in: Rect(x: list.x, y: list.y + index, width: list.width, height: 1), buffer: &buffer)
        }
        Scrollbar(total: lines.count, visible: list.height, offset: start)
            .render(column: width - 1, rows: list.y..<(list.y + list.height), buffer: &buffer)
        window.renderDivider(atRow: divider.y, in: buffer.area, buffer: &buffer)
        Self.hints.render(in: footer, buffer: &buffer)
        return buffer
    }

    private func bodyLines(wrappingTo width: Int? = nil) -> [[Span]] {
        var lines: [[Span]] = []
        for section in sections {
            if !lines.isEmpty { lines.append([]) }
            if let title = section.title { lines.append([Span(title, TextStyle(bold: true))]) }
            lines += section.rows.flatMap { Self.lines($0, wrappingTo: width) }
        }
        if let footnote {
            lines.append([])
            lines += width.map { Self.wrapped(footnote, style: TextStyle(dim: true), indent: "", width: $0) }
                ?? [[Span(footnote, TextStyle(dim: true))]]
        }
        return lines
    }

    private static func lines(_ row: InfoRow, wrappingTo width: Int?) -> [[Span]] {
        if let width, case .message(let spans) = row, spans.count == 1 {
            return wrapped(spans[0].text, style: spans[0].style, indent: "  ", width: width)
        }
        return [spans(row)]
    }

    private static func wrapped(_ text: String, style: TextStyle, indent: String, width: Int) -> [[Span]] {
        Term.wordWrap(text, width: max(1, width - indent.count)).map { [Span(indent), Span($0, style)] }
    }

    private static func spans(_ row: InfoRow) -> [Span] {
        switch row {
        case .metric(let label, let value, let note):
            let labelSpan = Span(Term.pad(label, to: labelWidth), TextStyle(dim: true))
            let noteSpans = note.map { [Span("  "), Span($0, TextStyle(dim: true))] } ?? []
            return [Span("  "), labelSpan, Span(" ")] + value + noteSpans
        case .gauge(let fraction, let color, let text):
            let filled = color.map { TextStyle(color: $0) } ?? .plain
            return [Span("  ")] + Gauge(fraction: fraction).spans(width: gaugeWidth, filled: filled) + [Span(" " + text)]
        case .message(let spans):
            return [Span("  ")] + spans
        }
    }

    private static func line(_ spans: [Span], colors: Bool) -> String {
        var buffer = Buffer(width: Term.displayWidth(spans), height: 1)
        buffer.write(spans, x: 0, y: 0)
        return buffer.lines(colors: colors)[0]
    }

    private static func write(_ spans: [Span], in rect: Rect, buffer: inout Buffer) {
        guard Term.displayWidth(spans) > rect.width else {
            buffer.write(spans, x: rect.x, y: rect.y, maxWidth: rect.width)
            return
        }
        let used = buffer.write(spans, x: rect.x, y: rect.y, maxWidth: rect.width - 1)
        buffer.write("…", x: rect.x + used, y: rect.y)
    }
}

struct InfoSection {
    var title: String?
    var rows: [InfoRow]
}

enum InfoRow {
    case metric(label: String, value: [Span], note: String?)
    case gauge(fraction: Double, color: TerminalColor?, text: String)
    case message([Span])
}

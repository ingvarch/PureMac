import TerminalUI

struct InfoSheet {
    var title: String
    var subtitle: String?
    var sections: [InfoSection]
    var footnote: String?

    private static let gaugeWidth = 20

    func plainLines(withHeader: Bool = true, colors: Bool = Term.colorEnabled) -> [String] {
        var lines: [[Span]] = []
        if withHeader {
            lines.append([Span(title, TextStyle(bold: true))])
            if let subtitle { lines.append([Span(subtitle, TextStyle(dim: true))]) }
            lines.append([])
        }
        return (lines + bodyLines()).map { Term.styled($0, colors: colors) }
    }

    private func bodyLines() -> [[Span]] {
        var lines: [[Span]] = []
        for section in sections {
            if !lines.isEmpty { lines.append([]) }
            if let title = section.title { lines.append([Span(title, TextStyle(bold: true))]) }
            lines += section.rows.flatMap { Self.lines($0, labelWidth: section.labelWidth, wrappingTo: nil) }
        }
        if let footnote {
            lines.append([])
            lines.append([Span(footnote, TextStyle(dim: true))])
        }
        return lines
    }

    static func lines(_ row: InfoRow, labelWidth: Int, indent: String = "  ", wrappingTo width: Int?) -> [[Span]] {
        switch row {
        case .metric(let label, let value, let note):
            let labelSpan = Span(Term.pad(label, to: labelWidth), TextStyle(dim: true))
            let noteSpans = note.map { [Span("  "), $0] } ?? []
            let row = [Span(indent), labelSpan, Span(" ")] + value + noteSpans
            guard let width, Term.displayWidth(row) > width else { return [row] }
            let deeper = indent + "  "
            return [[Span(indent), Span(label, TextStyle(dim: true))], [Span(deeper)] + fitted(value, to: width - deeper.count - Term.displayWidth(noteSpans)) + noteSpans]
        case .gauge(let fraction, let color, let text):
            let barWidth = width.map { min(gaugeWidth, $0 - indent.count - 1 - Term.displayWidth(text)) } ?? gaugeWidth
            let bar = Gauge(fraction: fraction).spans(width: barWidth, filled: color.map { TextStyle(color: $0) } ?? .plain)
            return [[Span(indent)] + bar + [Span(bar.isEmpty ? text : " " + text)]]
        case .path(let path):
            return [[Span(indent + path)]]
        case .message(let spans):
            guard let width else { return [[Span(indent)] + spans] }
            return wrapped(spans, indent: indent, width: width)
        }
    }

    private static func fitted(_ spans: [Span], to width: Int) -> [Span] {
        guard spans.count == 1, let span = spans.first else { return spans }
        return [Span(Term.truncate(span.text, to: max(1, width), middle: true), span.style)]
    }

    private static func wrapped(_ spans: [Span], indent: String, width: Int) -> [[Span]] {
        Term.wordWrap(spans, width: max(1, width - indent.count)).map { [Span(indent)] + $0 }
    }

    static func write(_ spans: [Span], in rect: Rect, buffer: inout Buffer) {
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
    var labelWidth = 17
    var rows: [InfoRow]
}

enum InfoRow {
    case metric(label: String, value: [Span], note: Span?)
    case gauge(fraction: Double, color: TerminalColor?, text: String)
    case message([Span])
    case path(String)
}

struct InfoSheetScroll {
    private(set) var offset = 0

    mutating func handle(_ key: TerminalKey, maxOffset: Int) -> Bool {
        switch key {
        case .up: offset = max(0, min(offset, maxOffset) - 1)
        case .down: offset = min(maxOffset, offset + 1)
        case .escape, .enter, .left, .backspace: return true
        case .character(let character): return character.lowercased() == "q"
        default: break
        }
        return false
    }
}

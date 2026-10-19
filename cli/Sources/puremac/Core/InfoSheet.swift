import TerminalUI

struct InfoSheet {
    var title: String
    var subtitle: String?
    var sections: [InfoSection]
    var footnote: String?

    private static let backHint = KeyHint("Esc", "back")
    private static let hints = KeyHints([KeyHint("↑↓", "scroll"), backHint])
    private static let gaugeWidth = 20

    private var window: Window { Window(title: title) }

    static func loading(title: String, _ build: () throws -> InfoSheet) -> InfoSheet {
        do {
            return try build()
        } catch {
            let message = Span(error.localizedDescription, TextStyle(color: .red))
            return InfoSheet(title: title, subtitle: nil, sections: [InfoSection(title: nil, rows: [.message([message])])], footnote: nil)
        }
    }

    func plainLines(withHeader: Bool = true, colors: Bool = Term.colorEnabled) -> [String] {
        var lines: [[Span]] = []
        if withHeader {
            lines.append([Span(title, TextStyle(bold: true))])
            if let subtitle { lines.append([Span(subtitle, TextStyle(dim: true))]) }
            lines.append([])
        }
        return (lines + bodyLines()).map { Term.styled($0, colors: colors) }
    }

    func render(width: Int, height: Int, offset: Int) -> Buffer {
        guard TooSmallScreen.fits(width: width, height: height) else {
            return TooSmallScreen.render(title: title, exitHint: "\(Self.backHint.key) \(Self.backHint.action)", width: width, height: height)
        }
        var buffer = Buffer(width: width, height: height)
        window.render(in: buffer.area, buffer: &buffer)
        let layout = layout(width: width, height: height)
        let list = layout.list
        let start = max(0, min(offset, layout.maxOffset))
        for (index, spans) in layout.lines.dropFirst(start).prefix(list.height).enumerated() {
            Self.write(spans, in: Rect(x: list.x, y: list.y + index, width: list.width, height: 1), buffer: &buffer)
        }
        Scrollbar(total: layout.lines.count, visible: list.height, offset: start)
            .render(column: width - 1, rows: list.y..<(list.y + list.height), buffer: &buffer)
        window.renderDivider(atRow: layout.divider.y, in: buffer.area, buffer: &buffer)
        Self.hints.render(in: layout.footer, buffer: &buffer)
        return buffer
    }

    func maxOffset(width: Int, height: Int) -> Int {
        guard TooSmallScreen.fits(width: width, height: height) else { return 0 }
        return layout(width: width, height: height).maxOffset
    }

    func show(in session: TerminalSession) {
        var scroll = InfoSheetScroll()
        while true {
            session.draw(render(width: session.width, height: session.height, offset: scroll.offset))
            if scroll.handle(session.readKey(), maxOffset: maxOffset(width: session.width, height: session.height)) { return }
        }
    }

    private struct Layout {
        var list: Rect
        var divider: Rect
        var footer: Rect
        var lines: [[Span]]
        var maxOffset: Int { max(0, lines.count - list.height) }
    }

    private func layout(width: Int, height: Int) -> Layout {
        let content = window.contentRect(in: Rect(x: 0, y: 0, width: width, height: height))
        let areas = content.splitRows([.fill, .length(1), .length(Self.hints.rows(width: content.width).count)])
        let list = areas[0]
        var lines = bodyLines(wrappingTo: list.width)
        if let subtitle {
            lines = Self.wrapped([Span(subtitle, TextStyle(dim: true))], indent: "", width: list.width) + [[]] + lines
        }
        return Layout(list: list, divider: areas[1], footer: areas[2], lines: lines)
    }

    private func bodyLines(wrappingTo width: Int? = nil) -> [[Span]] {
        var lines: [[Span]] = []
        for section in sections {
            if !lines.isEmpty { lines.append([]) }
            if let title = section.title { lines.append([Span(title, TextStyle(bold: true))]) }
            lines += section.rows.flatMap { Self.lines($0, labelWidth: section.labelWidth, wrappingTo: width) }
        }
        if let footnote {
            lines.append([])
            let note = [Span(footnote, TextStyle(dim: true))]
            lines += width.map { Self.wrapped(note, indent: "", width: $0) } ?? [note]
        }
        return lines
    }

    private static func lines(_ row: InfoRow, labelWidth: Int, wrappingTo width: Int?) -> [[Span]] {
        switch row {
        case .metric(let label, let value, let note):
            let labelSpan = Span(Term.pad(label, to: labelWidth), TextStyle(dim: true))
            let noteSpans = note.map { [Span("  "), $0] } ?? []
            let row = [Span("  "), labelSpan, Span(" ")] + value + noteSpans
            guard let width, Term.displayWidth(row) > width else { return [row] }
            return [[Span("  "), Span(label, TextStyle(dim: true))], [Span("    ")] + fitted(value, to: width - 4 - Term.displayWidth(noteSpans)) + noteSpans]
        case .gauge(let fraction, let color, let text):
            let barWidth = width.map { min(gaugeWidth, $0 - 3 - Term.displayWidth(text)) } ?? gaugeWidth
            let bar = Gauge(fraction: fraction).spans(width: barWidth, filled: color.map { TextStyle(color: $0) } ?? .plain)
            return [[Span("  ")] + bar + [Span(bar.isEmpty ? text : " " + text)]]
        case .path(let path):
            let shown = width.map { Term.truncate(path, to: max(1, $0 - 2), middle: true) } ?? path
            return [[Span("  " + shown)]]
        case .message(let spans):
            guard let width else { return [[Span("  ")] + spans] }
            return wrapped(spans, indent: "  ", width: width)
        }
    }

    private static func fitted(_ spans: [Span], to width: Int) -> [Span] {
        guard spans.count == 1, let span = spans.first else { return spans }
        return [Span(Term.truncate(span.text, to: max(1, width), middle: true), span.style)]
    }

    private static func wrapped(_ spans: [Span], indent: String, width: Int) -> [[Span]] {
        Term.wordWrap(spans, width: max(1, width - indent.count)).map { [Span(indent)] + $0 }
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

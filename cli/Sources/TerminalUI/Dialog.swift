public struct DialogButton: Equatable {
    public enum Role: Equatable { case normal, destructive }

    public var title: String
    public var role: Role

    public init(_ title: String, role: Role = .normal) {
        self.title = title
        self.role = role
    }
}

public struct Dialog {
    public var title: String
    public var titleStyle: TextStyle
    public var borderStyle: TextStyle
    public var message: [Span]
    public var buttons: [DialogButton]
    public var focusedButton: Int?
    public var hints: KeyHints?

    public init(
        title: String,
        titleStyle: TextStyle = TextStyle(bold: true),
        borderStyle: TextStyle = .plain,
        message: [Span] = [],
        buttons: [DialogButton] = [],
        focusedButton: Int? = nil,
        hints: KeyHints? = nil
    ) {
        self.title = title
        self.titleStyle = titleStyle
        self.borderStyle = borderStyle
        self.message = message
        self.buttons = buttons
        self.focusedButton = focusedButton
        self.hints = hints
    }

    public static func maxContentWidth(in area: Rect) -> Int {
        max(1, area.width - 8)
    }

    public func frame(in area: Rect) -> Rect {
        placement(in: area).frame
    }

    public func render(in area: Rect, buffer: inout Buffer) {
        let (frame, layout) = placement(in: area)
        buffer.clear(frame)
        let content = Window(title: title, borderStyle: borderStyle, titleStyle: titleStyle)
            .render(in: frame, buffer: &buffer)
        var row = content.y + layout.blankAboveMessage
        for message in layout.messageRows {
            renderCentered([message], in: content, row: row, buffer: &buffer)
            row += 1
        }
        row += layout.blankBelowMessage
        if !buttons.isEmpty {
            renderButtons(in: content, row: row, buffer: &buffer)
            row += 1
        }
        row += layout.blankBelowButtons
        for spans in hints?.rows(width: content.width) ?? [] {
            renderCentered(spans, in: content, row: row, buffer: &buffer)
            row += 1
        }
    }

    private struct Layout {
        var messageRows: [Span]
        var blankAboveMessage = 0
        var blankBelowMessage = 0
        var blankBelowButtons = 0
        var hintRows: Int
        var buttonRows: Int
        var height: Int {
            messageRows.count + blankAboveMessage + blankBelowMessage + blankBelowButtons + buttonRows + hintRows
        }
    }

    private func placement(in area: Rect) -> (frame: Rect, layout: Layout) {
        let contentWidth = self.contentWidth(maxWidth: Dialog.maxContentWidth(in: area))
        let layout = layout(contentWidth: contentWidth, maxRows: area.height - 4)
        let width = contentWidth + 4
        let height = layout.height + 2
        let frame = Rect(
            x: area.x + (area.width - width) / 2,
            y: area.y + (area.height - height) / 2,
            width: width,
            height: height
        )
        return (frame, layout)
    }

    private var buttonSpans: [Span] {
        var spans: [Span] = []
        for (index, button) in buttons.enumerated() {
            if index > 0 { spans.append(Span("  ")) }
            let title = Term.sanitize(button.title)
            let focused = index == focusedButton
            let style = TextStyle(color: button.role == .destructive ? .red : nil, inverse: focused)
            spans.append(Span(focused ? "› \(title) ‹" : "[ \(title) ]", style))
        }
        return spans
    }

    private func contentWidth(maxWidth: Int) -> Int {
        let titleWidth = Term.displayWidth(Term.sanitize(title)) + 2
        let messageWidth = message.map { Term.displayWidth(Term.sanitize($0.text)) }.max() ?? 0
        let buttonsWidth = Term.displayWidth(buttonSpans)
        let hintWidth = hints?.rows(width: .max).first.map(Term.displayWidth) ?? 0
        return max(1, min(max(titleWidth, messageWidth, buttonsWidth, hintWidth), maxWidth))
    }

    private func layout(contentWidth: Int, maxRows: Int) -> Layout {
        let hintRows = hints?.rows(width: contentWidth).count ?? 0
        let buttonRows = buttons.isEmpty ? 0 : 1
        let tailRows = buttonRows + hintRows
        let wrapped = message.flatMap { paragraph in
            Term.wordWrap(paragraph.text, width: contentWidth).map { Span($0, paragraph.style) }
        }
        var layout = Layout(messageRows: wrapped, hintRows: hintRows, buttonRows: buttonRows)
        if !wrapped.isEmpty {
            layout.blankAboveMessage = 1
            layout.blankBelowMessage = tailRows > 0 ? 1 : 0
        }
        layout.blankBelowButtons = buttonRows > 0 && hintRows > 0 ? 1 : 0
        if layout.height > maxRows { layout.blankBelowButtons = 0 }
        if layout.height > maxRows { layout.blankBelowMessage = 0 }
        if layout.height > maxRows { layout.blankAboveMessage = 0 }
        layout.messageRows = Array(wrapped.prefix(max(0, maxRows - layout.height + wrapped.count)))
        return layout
    }

    private func renderCentered(_ spans: [Span], in content: Rect, row: Int, buffer: inout Buffer) {
        let width = Term.displayWidth(spans)
        let column = content.x + max(0, content.width - width) / 2
        buffer.write(spans, x: column, y: row, maxWidth: content.x + content.width - column)
    }

    private func renderButtons(in content: Rect, row: Int, buffer: inout Buffer) {
        renderCentered(buttonSpans, in: content, row: row, buffer: &buffer)
    }
}

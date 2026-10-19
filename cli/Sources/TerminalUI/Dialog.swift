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
        var row = content.y
        for message in layout.messageRows {
            buffer.write([message], x: content.x, y: row, maxWidth: content.width)
            row += 1
        }
        row += layout.blankRows
        if !buttons.isEmpty {
            renderButtons(in: content, row: row, buffer: &buffer)
            row += 1
        }
        hints?.render(in: Rect(x: content.x, y: row, width: content.width, height: layout.hintRows), buffer: &buffer)
    }

    private struct Layout {
        var messageRows: [Span]
        var blankRows: Int
        var hintRows: Int
        var buttonRows: Int
        var height: Int { messageRows.count + blankRows + buttonRows + hintRows }
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

    private var buttonLabels: [String] {
        buttons.indices.map { index in
            let title = Term.sanitize(buttons[index].title)
            return index == focusedButton ? "› \(title) ‹" : "[ \(title) ]"
        }
    }

    private var buttonsWidth: Int {
        guard !buttons.isEmpty else { return 0 }
        return buttonLabels.reduce(0) { $0 + Term.displayWidth($1) } + 2 * (buttons.count - 1)
    }

    private func contentWidth(maxWidth: Int) -> Int {
        let titleWidth = Term.displayWidth(Term.sanitize(title)) + 2
        let messageWidth = message.map { Term.displayWidth(Term.sanitize($0.text)) }.max() ?? 0
        let hintWidth = hints?.rows(width: .max).first?.reduce(0) { $0 + Term.displayWidth($1.text) } ?? 0
        return max(1, min(max(titleWidth, messageWidth, buttonsWidth, hintWidth), maxWidth))
    }

    private func layout(contentWidth: Int, maxRows: Int) -> Layout {
        let hintRows = hints?.rows(width: contentWidth).count ?? 0
        let buttonRows = buttons.isEmpty ? 0 : 1
        let tailRows = buttonRows + hintRows
        let wrapped = message.flatMap { paragraph in
            Term.wordWrap(paragraph.text, width: contentWidth).map { Span($0, paragraph.style) }
        }
        let blankRows = tailRows > 0 && wrapped.count + 1 + tailRows <= maxRows ? 1 : 0
        let messageRows = Array(wrapped.prefix(max(0, maxRows - blankRows - tailRows)))
        return Layout(messageRows: messageRows, blankRows: blankRows, hintRows: hintRows, buttonRows: buttonRows)
    }

    private func renderButtons(in content: Rect, row: Int, buffer: inout Buffer) {
        var column = max(content.x, content.x + content.width - buttonsWidth)
        for (index, label) in buttonLabels.enumerated() {
            let focused = index == focusedButton
            let style = TextStyle(color: buttons[index].role == .destructive ? .red : nil, inverse: focused)
            column += buffer.write(label, x: column, y: row, style: style, maxWidth: content.x + content.width - column) + 2
        }
    }
}

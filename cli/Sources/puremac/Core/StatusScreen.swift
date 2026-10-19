import TerminalUI

enum StatusScreen {
    static let warningTitle = TextStyle(color: .yellow, bold: true)
    static let cancelHint = KeyHint("Ctrl+C", "cancel")
    static let warningBorder = TextStyle(color: .yellow)
    static let choiceHints = KeyHints([KeyHint("Enter", "select"), KeyHint("Esc", "back")])

    static func render(
        title: String,
        message: String,
        detail: String?,
        hint: KeyHint,
        width: Int,
        height: Int
    ) -> Buffer {
        let hints = KeyHints([hint])
        guard TooSmallScreen.fits(width: width, height: height) else {
            return TooSmallScreen.render(title: title, exitHint: "\(hint.key) \(hint.action)", width: width, height: height)
        }
        var buffer = Buffer(width: width, height: height)
        let window = Window(title: title)
        let content = window.render(in: buffer.area, buffer: &buffer)
        let areas = content.splitRows([.length(2), .fill, .length(1), .length(hints.rows(width: content.width).count)])
        let (header, divider, footer) = (areas[0], areas[2], areas[3])

        buffer.write(Term.truncate(message, to: header.width), x: header.x, y: header.y, style: TextStyle(dim: true))
        if let detail {
            buffer.write(Term.truncate(detail, to: header.width, middle: true), x: header.x, y: header.y + 1)
        }
        window.renderDivider(atRow: divider.y, in: buffer.area, buffer: &buffer)
        hints.render(in: footer, buffer: &buffer)
        return buffer
    }

    static func overlay(_ dialog: Dialog, on background: Buffer, tooSmallExitHint: String? = nil) -> Buffer {
        guard TooSmallScreen.fits(width: background.width, height: background.height) else {
            guard let tooSmallExitHint else { return background }
            return TooSmallScreen.render(
                title: "PureMac", exitHint: tooSmallExitHint, width: background.width, height: background.height
            )
        }
        var buffer = background
        buffer.fade()
        dialog.render(in: buffer.area, buffer: &buffer)
        return buffer
    }
}

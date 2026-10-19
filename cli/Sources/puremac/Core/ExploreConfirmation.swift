import TerminalUI

enum ExploreChoice: Equatable {
    case start, back
}

struct ExploreConfirmation {
    private static let buttons = [DialogButton("Cancel"), DialogButton("Start")]
    static let startIndex = buttons.count - 1

    private(set) var focus = ButtonFocus(count: buttons.count, index: startIndex)

    mutating func handle(_ key: TerminalKey) -> ExploreChoice? {
        if focus.navigate(key) { return nil }
        switch key {
        case .enter:
            return focus.index == Self.startIndex ? .start : .back
        case .escape:
            return .back
        case .character(let character):
            switch String(character).lowercased() {
            case "s": return .start
            case "q", "n": return .back
            default: return nil
            }
        default:
            return nil
        }
    }

    func render(width: Int, height: Int) -> Buffer {
        let menu = TerminalMenu.render(
            title: HomeMenu.title,
            subtitle: HomeMenu.subtitle,
            options: HomeMenu.options,
            selection: HomeMenu.exploreIndex,
            width: width,
            height: height
        )
        return StatusScreen.overlay(dialog, on: menu, tooSmallExitHint: "Esc back")
    }

    static func ask() throws -> Bool {
        let session = try TerminalSession()
        defer { session.close() }
        var model = ExploreConfirmation()
        while true {
            session.draw(model.render(width: session.width, height: session.height))
            if let choice = model.handle(session.readKey()) { return choice == .start }
        }
    }

    private var dialog: Dialog {
        Dialog(
            title: "Explore your home folder?",
            message: [Span("Measuring every folder can take a few minutes.")],
            buttons: Self.buttons,
            focusedButton: focus.index,
            hints: StatusScreen.choiceHints
        )
    }
}

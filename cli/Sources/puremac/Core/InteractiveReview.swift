import Foundation
import TerminalUI

struct ReviewAddress: Hashable {
    let category: Int
    let group: Int
    let item: Int
}

enum ReviewDisplayRow {
    case category(Int)
    case group(category: Int, group: Int)
    case item(ReviewAddress)
}

struct InteractiveReviewModel {
    var categories: [CategoryScan]
    var query = ""
    var isSearching = false
    var isReviewing = false
    var status = ""
    var pathOffset = 0
    private(set) var focus = 0
    private(set) var reviewFocus = 0

    init(categories: [CategoryScan]) {
        self.categories = categories.map { category in
            var copy = category
            copy.groups = copy.groups.map { group in
                var groupCopy = group
                groupCopy.items = groupCopy.items.map { item in
                    var itemCopy = item
                    itemCopy.selected = false
                    return itemCopy
                }
                return groupCopy
            }
            return copy
        }
    }

    var matchingAddresses: [ReviewAddress] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var addresses: [ReviewAddress] = []
        for categoryIndex in categories.indices {
            let category = categories[categoryIndex]
            for groupIndex in category.groups.indices {
                let group = category.groups[groupIndex]
                for itemIndex in group.items.indices {
                    let item = group.items[itemIndex]
                    let searchable = "\(category.title) \(group.tool) \(item.path)".lowercased()
                    if needle.isEmpty || searchable.contains(needle) {
                        addresses.append(
                            ReviewAddress(
                                category: categoryIndex,
                                group: groupIndex,
                                item: itemIndex
                            )
                        )
                    }
                }
            }
        }
        return addresses
    }

    var selectedAddresses: [ReviewAddress] {
        allAddresses.filter { item(at: $0).selected }
    }

    var selectedCount: Int {
        selectedAddresses.count
    }

    var selectedBytes: Int64 {
        selectedAddresses.reduce(Int64(0)) { $0 + item(at: $1).sizeBytes }
    }

    var allBytes: Int64 {
        categories.reduce(Int64(0)) { $0 + $1.allBytes }
    }

    var focusedAddress: ReviewAddress? {
        let addresses = isReviewing ? selectedAddresses : matchingAddresses
        let index = isReviewing ? reviewFocus : focus
        guard addresses.indices.contains(index) else { return nil }
        return addresses[index]
    }

    mutating func move(_ delta: Int) {
        let count = isReviewing ? selectedAddresses.count : matchingAddresses.count
        guard count > 0 else { return }
        if isReviewing {
            reviewFocus = min(count - 1, max(0, reviewFocus + delta))
        } else {
            focus = min(count - 1, max(0, focus + delta))
        }
        pathOffset = 0
    }

    mutating func moveToStart() {
        if isReviewing {
            reviewFocus = 0
        } else {
            focus = 0
        }
        pathOffset = 0
    }

    mutating func moveToEnd() {
        if isReviewing {
            reviewFocus = max(0, selectedAddresses.count - 1)
        } else {
            focus = max(0, matchingAddresses.count - 1)
        }
        pathOffset = 0
    }

    mutating func toggleFocused() {
        guard !isReviewing, let address = focusedAddress else { return }
        categories[address.category].groups[address.group].items[address.item].selected.toggle()
    }

    mutating func selectAllMatching() {
        for address in matchingAddresses {
            categories[address.category].groups[address.group].items[address.item].selected = true
        }
        status = matchingAddresses.isEmpty ? "No matching items" : "Selected visible items"
    }

    mutating func selectNone() {
        for address in allAddresses {
            categories[address.category].groups[address.group].items[address.item].selected = false
        }
        reviewFocus = 0
        status = "Selection cleared"
    }

    mutating func updateQuery(_ value: String) {
        query = value
        focus = 0
        pathOffset = 0
        status = ""
    }

    mutating func beginReview() -> Bool {
        guard selectedCount > 0 else {
            status = "Select at least one item to continue"
            return false
        }
        isReviewing = true
        reviewFocus = 0
        pathOffset = 0
        status = ""
        return true
    }

    mutating func endReview() {
        isReviewing = false
        pathOffset = 0
        status = ""
    }

    func displayRows(reviewing: Bool) -> [ReviewDisplayRow] {
        let addresses = reviewing ? selectedAddresses : matchingAddresses
        var rows: [ReviewDisplayRow] = []
        var lastCategory: Int?
        var lastGroup: Int?
        for address in addresses {
            if lastCategory != address.category {
                rows.append(.category(address.category))
                lastCategory = address.category
                lastGroup = nil
            }
            if lastGroup != address.group {
                rows.append(.group(category: address.category, group: address.group))
                lastGroup = address.group
            }
            rows.append(.item(address))
        }
        return rows
    }

    func item(at address: ReviewAddress) -> ScanItem {
        categories[address.category].groups[address.group].items[address.item]
    }

    func selectedResult() -> [CategoryScan] {
        categories
    }

    private var allAddresses: [ReviewAddress] {
        var addresses: [ReviewAddress] = []
        for categoryIndex in categories.indices {
            for groupIndex in categories[categoryIndex].groups.indices {
                for itemIndex in categories[categoryIndex].groups[groupIndex].items.indices {
                    addresses.append(
                        ReviewAddress(
                            category: categoryIndex,
                            group: groupIndex,
                            item: itemIndex
                        )
                    )
                }
            }
        }
        return addresses
    }
}

enum InteractiveReview {
    static func select(_ categories: [CategoryScan], title: String) throws -> [CategoryScan]? {
        let session = try TerminalSession()
        defer { session.close() }

        var model = InteractiveReviewModel(categories: categories)
        while true {
            session.draw(render(model: model, title: title, width: session.width, height: session.height))
            let key = session.readKey()

            if model.isSearching {
                switch key {
                case .enter:
                    model.isSearching = false
                case .escape:
                    model.isSearching = false
                    model.updateQuery("")
                case .backspace, .delete:
                    if !model.query.isEmpty {
                        model.updateQuery(String(model.query.dropLast()))
                    }
                case .space:
                    model.updateQuery(model.query + " ")
                case .character(let character):
                    if !character.isASCIIControl {
                        model.updateQuery(model.query + String(character))
                    }
                default:
                    break
                }
                continue
            }

            switch key {
            case .up:
                model.move(-1)
            case .down:
                model.move(1)
            case .pageUp:
                model.move(-max(1, session.height / 2))
            case .pageDown:
                model.move(max(1, session.height / 2))
            case .home:
                model.moveToStart()
            case .end:
                model.moveToEnd()
            case .left:
                model.pathOffset = max(0, model.pathOffset - max(8, session.width / 3))
            case .right:
                model.pathOffset += max(8, session.width / 3)
            case .space:
                model.toggleFocused()
            case .enter:
                if model.isReviewing {
                    return model.selectedResult()
                }
                _ = model.beginReview()
            case .escape:
                if model.isReviewing {
                    model.endReview()
                } else {
                    return nil
                }
            case .character(let character):
                switch character.lowercasedString {
                case "a":
                    if !model.isReviewing { model.selectAllMatching() }
                case "n":
                    if !model.isReviewing { model.selectNone() }
                case "/":
                    if !model.isReviewing {
                        model.isSearching = true
                        model.status = ""
                    }
                case "q":
                    return nil
                default:
                    break
                }
            default:
                break
            }
        }
    }

    private static let itemPrefixWidth = 5 + Render.sizeColumnWidth
    private static let summaryGap = 2

    static func render(
        model: InteractiveReviewModel,
        title: String,
        width: Int,
        height: Int
    ) -> Buffer {
        guard TooSmallScreen.fits(width: width, height: height) else {
            return TooSmallScreen.render(title: "PureMac", exitHint: "Esc/q cancel", width: width, height: height)
        }
        var buffer = Buffer(width: width, height: height)
        let reviewing = model.isReviewing
        let accent = TextStyle(color: .yellow)
        let window = Window(
            title: reviewing ? "Final review" : title,
            info: "\(model.selectedCount) selected · \(ByteCount.human(model.selectedBytes))",
            borderStyle: reviewing ? accent : TextStyle(dim: true),
            titleStyle: TextStyle(color: reviewing ? .yellow : .cyan, bold: true)
        )
        let content = window.render(in: buffer.area, buffer: &buffer)
        let hints = KeyHints(reviewing ? reviewHints : selectHints)
        let areas = content.splitRows(
            [.length(1), .fill, .length(1), .length(1), .length(hints.rows(width: content.width).count), .length(reviewing ? 1 : 0)]
        )
        let (header, list, divider, path, footer, confirmation) = (areas[0], areas[1], areas[2], areas[3], areas[4], areas[5])

        renderHeader(model: model, in: header, buffer: &buffer)
        window.renderDivider(atRow: divider.y, in: buffer.area, buffer: &buffer)
        buffer.write(focusedPathSpans(model: model, width: path.width), x: path.x, y: path.y, maxWidth: path.width)
        hints.render(in: footer, buffer: &buffer)
        if reviewing {
            buffer.write("Command confirmation follows", x: confirmation.x, y: confirmation.y, style: accent, maxWidth: confirmation.width)
        }

        let rows = model.displayRows(reviewing: reviewing)
        let focusedAddress = model.focusedAddress
        let focusedRow = rows.firstIndex { row in
            if case .item(let address) = row { return address == focusedAddress }
            return false
        } ?? 0
        let start = Scrollbar.centeredOffset(total: rows.count, visible: list.height, focus: focusedRow)
        for (index, row) in rows.enumerated().dropFirst(start).prefix(list.height) {
            let rect = Rect(x: list.x, y: list.y + index - start, width: list.width, height: 1)
            renderRow(row, focused: focusedAddress, model: model, in: rect, buffer: &buffer)
        }
        Scrollbar(total: rows.count, visible: list.height, offset: start)
            .render(column: width - 1, rows: list.y..<(list.y + list.height), buffer: &buffer)
        return buffer
    }

    private static let selectHints = [
        KeyHint("↑↓", "move"),
        KeyHint("←→", "path"),
        KeyHint("Space", "toggle"),
        KeyHint("A", "all"),
        KeyHint("N", "none"),
        KeyHint("/", "search"),
        KeyHint("Enter", "review"),
        KeyHint("Esc/q", "cancel")
    ]

    private static let reviewHints = [
        KeyHint("↑↓", "scroll"),
        KeyHint("←→", "path"),
        KeyHint("Enter", "confirm"),
        KeyHint("Esc", "edit"),
        KeyHint("q", "cancel")
    ]

    private static func renderHeader(model: InteractiveReviewModel, in rect: Rect, buffer: inout Buffer) {
        let dim = TextStyle(dim: true)
        let found = "\(model.matchingAddresses.count) shown · \(ByteCount.human(model.allBytes))"
        let left: [Span]
        if model.isSearching {
            let label = "Search  "
            let query = Term.truncate(model.query, to: max(1, rect.width - label.count - 1))
            left = [Span(label, TextStyle(color: .cyan)), Span(query), Span(" ", TextStyle(inverse: true))]
        } else if !model.status.isEmpty {
            left = [Span(Term.truncate(model.status, to: rect.width), TextStyle(color: .yellow))]
        } else if !model.query.isEmpty {
            let label = "Filter  "
            left = [Span(label + Term.truncate(model.query, to: max(1, rect.width - label.count)), dim)]
        } else {
            buffer.write(Term.truncate(found, to: rect.width), x: rect.x, y: rect.y, style: dim)
            return
        }
        let leftWidth = buffer.write(left, x: rect.x, y: rect.y, maxWidth: rect.width)
        let foundWidth = Term.displayWidth(found)
        if leftWidth + summaryGap + foundWidth <= rect.width {
            buffer.write(found, x: rect.x + rect.width - foundWidth, y: rect.y, style: dim)
        }
    }

    private static func renderRow(
        _ row: ReviewDisplayRow,
        focused focusedAddress: ReviewAddress?,
        model: InteractiveReviewModel,
        in rect: Rect,
        buffer: inout Buffer
    ) {
        switch row {
        case .category(let categoryIndex):
            let title = Term.truncate(model.categories[categoryIndex].title, to: rect.width)
            buffer.write(title, x: rect.x, y: rect.y, style: TextStyle(bold: true), maxWidth: rect.width)
        case .group(let categoryIndex, let groupIndex):
            let group = model.categories[categoryIndex].groups[groupIndex]
            let suffix = "\(group.items.count) \(group.items.count == 1 ? "item" : "items")"
            let label = Term.truncate(group.tool, to: max(1, rect.width - suffix.count - 1))
            buffer.write(
                Term.pad(label, to: rect.width - suffix.count) + suffix,
                x: rect.x,
                y: rect.y,
                style: TextStyle(dim: true),
                maxWidth: rect.width
            )
        case .item(let address):
            let item = model.item(at: address)
            let focused = address == focusedAddress
            let rowStyle = TextStyle(inverse: focused)
            let sizeStyle = SizeLevel.style(bytes: item.sizeBytes, focused: focused)
            let pathWidth = max(1, rect.width - itemPrefixWidth)
            let path = Term.truncate(Render.shorten(item.path), to: pathWidth, middle: true)
            buffer.write(
                [
                    FocusPointer.span(focused: focused),
                    Span(" ", rowStyle),
                    Span(item.selected ? "●" : "○", TextStyle(color: item.selected ? .cyan : nil, dim: !item.selected, inverse: focused)),
                    Span(" ", rowStyle),
                    Span(Render.sizeCol(item.sizeBytes), sizeStyle),
                    Span(" " + Term.pad(path, to: pathWidth), rowStyle)
                ],
                x: rect.x,
                y: rect.y,
                maxWidth: rect.width
            )
        }
    }

    private static func focusedPathSpans(model: InteractiveReviewModel, width: Int) -> [Span] {
        let label = TextStyle(dim: true)
        guard let address = model.focusedAddress else {
            return [Span("Path  No matching item", label)]
        }
        let path = Render.shorten(model.item(at: address).path)
        let window = horizontalWindow(path, offset: model.pathOffset, width: max(1, width - 6))
        return [Span("Path  ", label), Span(window)]
    }

    static func horizontalWindow(_ value: String, offset: Int, width: Int) -> String {
        let safe = Term.sanitize(value)
        let characters = Array(safe)
        let start = min(max(0, offset), characters.count)
        let prefixMarker = start > 0 ? "‹" : ""
        var output = ""
        var used = Term.displayWidth(prefixMarker)
        var index = start

        while index < characters.count {
            let value = String(characters[index])
            let characterWidth = Term.displayWidth(value)
            let remainingMarker = index + 1 < characters.count ? 1 : 0
            guard used + characterWidth + remainingMarker <= width else { break }
            output.append(characters[index])
            used += characterWidth
            index += 1
        }
        let suffixMarker = index < characters.count ? "›" : ""
        return prefixMarker + output + suffixMarker
    }
}

private extension Character {
    var isASCIIControl: Bool {
        unicodeScalars.allSatisfy { $0.value < 0x20 || $0.value == 0x7F }
    }

    var lowercasedString: String {
        String(self).lowercased()
    }
}

import ArgumentParser
import Foundation
import TerminalUI

struct Analyze: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show what is taking up disk space, largest first.",
        discussion: """
        Sizes the immediate children of a folder and ranks them, like `du -d1 | sort`.
          puremac analyze              Explore your home folder
          puremac analyze ~/Library    Explore a specific folder
          puremac analyze --plain      Print a report without fullscreen browsing
        Browsing never modifies files.
        """
    )

    @Argument(help: "Folder to analyze. Omit for your home folder.")
    var path: String?

    @Option(name: .shortAndLong, help: "How many levels deep to print in plain mode (1...8).")
    var depth: Int = 1

    @Flag(name: .long, help: "Emit machine-readable JSON and exit.")
    var json = false

    @Flag(name: .long, help: "Print a report instead of opening the fullscreen explorer.")
    var plain = false

    func validate() throws {
        guard (1...8).contains(depth) else {
            throw ValidationError("Depth must be between 1 and 8.")
        }
    }

    func run() throws {
        let target = ((path ?? Safety.home) as NSString).expandingTildeInPath
        let ignore = try IgnoreStore(fileURL: AppPaths.ignoreFile)
        try validateRoot(target, ignore: ignore)

        if json {
            let snapshot = scanFolder(target, ignore: ignore)
            struct Row: Encodable { let path: String; let bytes: Int64 }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let data = try encoder.encode(snapshot.children.map { Row(path: $0.path, bytes: $0.size) })
            print(String(decoding: data, as: UTF8.self))
            return
        }

        if Self.usesInteractiveBrowser(plain: plain, depth: depth) {
            try browse(target, ignore: ignore)
            return
        }

        printPlain(target, ignore: ignore)
    }

    static func usesInteractiveBrowser(
        plain: Bool,
        depth: Int,
        terminalSupported: Bool = TerminalSession.isSupported
    ) -> Bool {
        !plain && depth == 1 && terminalSupported
    }

    struct Child: Equatable {
        let path: String
        let size: Int64
        let isDir: Bool
        let isPackage: Bool
        let inaccessibleCount: Int
        let skippedCount: Int

        var isPartial: Bool { inaccessibleCount > 0 || skippedCount > 0 }
    }

    struct FolderSnapshot: Equatable {
        let path: String
        let children: [Child]
        let total: Int64
        let inaccessibleCount: Int
        let skippedCount: Int
        let errors: [String]

        var isPartial: Bool { inaccessibleCount > 0 || skippedCount > 0 }
    }

    private struct MeasureContext {
        var inaccessibleCount = 0
        var skippedCount = 0
        var errors: [String] = []
    }

    struct BrowserLevel {
        let snapshot: FolderSnapshot
        var selected = 0
        var offset = 0
    }

    func scanFolder(_ directory: String, ignore: IgnoreStore = IgnoreStore()) -> FolderSnapshot {
        let standardized = (directory as NSString).standardizingPath
        let directoryURL = URL(fileURLWithPath: standardized, isDirectory: true)
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: standardized)
        } catch {
            return FolderSnapshot(
                path: standardized,
                children: [],
                total: 0,
                inaccessibleCount: 1,
                skippedCount: 0,
                errors: ["\(standardized): \(error.localizedDescription)"]
            )
        }

        var context = MeasureContext()
        var children: [Child] = []
        let orderedNames = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for name in orderedNames {
            let url = directoryURL.appendingPathComponent(name)
            if let child = measureChild(url, ignore: ignore, context: &context) {
                children.append(child)
            }
        }

        children.sort {
            if $0.size == $1.size {
                return URL(fileURLWithPath: $0.path).lastPathComponent
                    .localizedStandardCompare(URL(fileURLWithPath: $1.path).lastPathComponent) == .orderedAscending
            }
            return $0.size > $1.size
        }
        return FolderSnapshot(
            path: standardized,
            children: children,
            total: children.reduce(Int64(0)) { $0 + $1.size },
            inaccessibleCount: context.inaccessibleCount,
            skippedCount: context.skippedCount,
            errors: context.errors
        )
    }

    func sizedChildren(of directory: String) -> [Child] {
        scanFolder(directory).children
    }

    private func measureChild(_ topURL: URL, ignore: IgnoreStore, context: inout MeasureContext) -> Child? {
        let path = topURL.path
        if Safety.ignoredPathProtectsCandidate(path, ignore: ignore) {
            context.skippedCount += 1
            return nil
        }
        let measurement = DirSizer.measure(of: path)
        switch measurement.status {
        case .symlink, .cloudOrDataless:
            context.skippedCount += max(1, measurement.skippedEntries)
            return nil
        case .unavailable:
            context.inaccessibleCount += max(1, measurement.skippedEntries)
            if context.errors.count < 20 { context.errors.append("\(path): unavailable") }
            return nil
        case .partial:
            context.skippedCount += max(1, measurement.skippedEntries)
            if context.errors.count < 20 { context.errors.append("\(path): partial measurement") }
        case .complete:
            break
        }

        let values = try? topURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isDirectory = values?.isDirectory == true
        return Child(
            path: path,
            size: measurement.bytes,
            isDir: isDirectory,
            isPackage: isDirectory && values?.isPackage == true,
            inaccessibleCount: 0,
            skippedCount: measurement.status == .partial ? max(1, measurement.skippedEntries) : 0
        )
    }

    private func validateRoot(_ target: String, ignore: IgnoreStore) throws {
        let standardized = (target as NSString).standardizingPath
        guard !ignore.isIgnored(standardized) else { throw ValidationError("Ignored path: \(standardized)") }
        guard !Safety.hasSymlinkComponent(standardized) else {
            throw ValidationError("Symbolic links are not scanned: \(standardized)")
        }
        guard !Safety.isCloudOrDataless(standardized) else {
            throw ValidationError("Cloud-only folders must be downloaded before scanning: \(standardized)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ValidationError("Not a folder: \(standardized)")
        }
    }

    private func printPlain(_ target: String, ignore: IgnoreStore) {
        let snapshot = scanFolder(target, ignore: ignore)
        if let volume = try? SystemInfo.volumeStatus(target), volume.total > 0 {
            print("")
            print(Term.bold("\(ByteCount.human(volume.availableNow)) free of \(ByteCount.human(volume.total))"))
        }
        print(Term.dim("\(Render.shorten(target)) — \(ByteCount.human(snapshot.total))"))
        print("")
        printLevel(snapshot.children, total: snapshot.total, indent: "  ", depthLeft: depth - 1, ignore: ignore)
        printDiagnostics(snapshot, indent: "  ")
    }

    func printLevel(
        _ children: [Child],
        total: Int64,
        indent: String,
        depthLeft: Int,
        ignore: IgnoreStore = IgnoreStore()
    ) {
        for child in children where child.size > 0 || child.isPartial {
            let fraction = total > 0 ? Double(child.size) / Double(total) : 0
            let percentage = String(format: "%5.1f%%", fraction * 100)
            let size = ByteCount.human(child.size).padding(toLength: 10, withPad: " ", startingAt: 0)
            let suffix = child.isDir && !child.isPackage ? "/" : (child.isPackage ? " [package]" : "")
            let partial = child.isPartial ? Term.yellow(" !") : ""
            let name = URL(fileURLWithPath: child.path).lastPathComponent + suffix
            print("\(indent)\(size) \(Term.dim(percentage)) \(Term.bar(fraction: fraction, width: 20)) \(name)\(partial)")
            if depthLeft > 0 && child.isDir && !child.isPackage {
                let snapshot = scanFolder(child.path, ignore: ignore)
                printLevel(Array(snapshot.children.prefix(10)), total: child.size, indent: indent + "  ", depthLeft: depthLeft - 1, ignore: ignore)
                printDiagnostics(snapshot, indent: indent + "  ")
            }
        }
    }

    private func printDiagnostics(_ snapshot: FolderSnapshot, indent: String) {
        if snapshot.skippedCount > 0 {
            print(indent + Term.yellow("\(snapshot.skippedCount) skipped") + Term.dim(" (ignored, linked, or cloud-only)"))
        }
        if snapshot.inaccessibleCount > 0 {
            print(indent + Term.red("\(snapshot.inaccessibleCount) inaccessible"))
            for error in snapshot.errors.prefix(5) { Term.err(indent + "! " + error) }
        }
    }

    private func browse(_ target: String, ignore: IgnoreStore) throws {
        let session = try TerminalSession()
        defer { session.close() }
        session.draw(Self.renderMeasuring(target, width: session.width, height: session.height))
        var levels = [BrowserLevel(snapshot: scanFolder(target, ignore: ignore))]
        var running = true

        while running {
            let index = levels.index(before: levels.endIndex)
            let visibleRows = Self.visibleRowCount(snapshot: levels[index].snapshot, selected: levels[index].selected, width: session.width, height: session.height)
            levels[index].offset = Self.adjustedOffset(
                levels[index].offset,
                selected: levels[index].selected,
                count: levels[index].snapshot.children.count,
                visibleRows: visibleRows
            )
            session.draw(Self.renderBrowser(level: levels[index], width: session.width, height: session.height))

            switch session.readKey() {
            case .up:
                levels[index].selected = max(0, levels[index].selected - 1)
            case .down:
                levels[index].selected = min(max(0, levels[index].snapshot.children.count - 1), levels[index].selected + 1)
            case .pageUp:
                levels[index].selected = max(0, levels[index].selected - visibleRows)
            case .pageDown:
                levels[index].selected = min(max(0, levels[index].snapshot.children.count - 1), levels[index].selected + visibleRows)
            case .home:
                levels[index].selected = 0
            case .end:
                levels[index].selected = max(0, levels[index].snapshot.children.count - 1)
            case .enter, .right:
                guard let child = Self.focusedChild(levels[index]), child.isDir, !child.isPackage else { continue }
                session.draw(Self.renderMeasuring(child.path, width: session.width, height: session.height))
                levels.append(BrowserLevel(snapshot: scanFolder(child.path, ignore: ignore)))
            case .left, .backspace:
                if levels.count > 1 { levels.removeLast() }
            case .escape:
                running = false
            case .character(let character):
                switch character.lowercased() {
                case "q": running = false
                case "o":
                    if let child = Self.focusedChild(levels[index]) { Self.revealInFinder(child.path) }
                default: break
                }
            case .delete, .space, .tab, .unknown:
                break
            }
        }
    }

    static func renderMeasuring(_ path: String, width: Int, height: Int) -> Buffer {
        StatusScreen.render(
            title: windowTitle,
            message: "Measuring allocated space...",
            detail: path,
            hint: StatusScreen.cancelHint,
            width: width,
            height: height
        )
    }

    private static let windowTitle = "PureMac Space Explorer"
    private static let focusedLabel = "Focused: "
    private static let window = Window(title: windowTitle)
    private static let rowPrefixWidth = 4 + Render.sizeColumnWidth
    private static let minimumGaugeWidth = 6
    private static let maximumGaugeWidth = 20
    private static let gaugeReservedWidth = 32
    private static let headerRows = 2
    private static let dividerRows = 1
    private static let minimumListRows = 3
    private static let browserHints = KeyHints([
        KeyHint("↑↓", "move"),
        KeyHint("Enter/→", "open"),
        KeyHint("O", "reveal"),
        KeyHint("←/⌫", "back"),
        KeyHint("q/Esc", "exit")
    ])

    private struct BrowserLayout {
        let header: Rect
        let list: Rect
        let divider: Rect
        let path: Rect
        let error: Rect
        let footer: Rect
        let pathLines: [String]

        var visibleRows: Int { max(1, list.height) }
    }

    private static func layout(snapshot: FolderSnapshot, selected: Int, width: Int, height: Int) -> BrowserLayout {
        let content = window.contentRect(in: Rect(x: 0, y: 0, width: width, height: height))
        let focusedPath = snapshot.children.indices.contains(selected) ? snapshot.children[selected].path : snapshot.path
        let pathWidth = max(1, content.width - focusedLabel.count)
        let hintRows = browserHints.rows(width: content.width).count
        let errorRows = snapshot.errors.isEmpty ? 0 : 1
        let spareRows = content.height - headerRows - dividerRows - errorRows - hintRows - minimumListRows
        var pathLines = Term.wrap(focusedPath, width: pathWidth)
        let pathRows = min(pathLines.count, max(1, spareRows))
        var budget = pathRows * pathWidth
        while pathLines.count > pathRows && budget > 1 {
            pathLines = Term.wrap(Term.truncate(focusedPath, to: budget, middle: true), width: pathWidth)
            budget -= 1
        }
        let areas = content.splitRows(
            [.length(headerRows), .fill, .length(dividerRows), .length(pathRows), .length(errorRows), .length(hintRows)]
        )
        return BrowserLayout(
            header: areas[0],
            list: areas[1],
            divider: areas[2],
            path: areas[3],
            error: areas[4],
            footer: areas[5],
            pathLines: pathLines
        )
    }

    static func renderBrowser(level: BrowserLevel, width: Int, height: Int) -> Buffer {
        guard TooSmallScreen.fits(width: width, height: height) else {
            return TooSmallScreen.render(title: windowTitle, exitHint: "Esc/q exit", width: width, height: height)
        }
        var buffer = Buffer(width: width, height: height)
        let snapshot = level.snapshot
        window.render(in: buffer.area, buffer: &buffer)
        let layout = layout(snapshot: snapshot, selected: level.selected, width: width, height: height)

        buffer.write(
            Term.truncate(snapshot.path, to: layout.header.width, middle: true),
            x: layout.header.x,
            y: layout.header.y,
            style: TextStyle(bold: true)
        )
        buffer.write(
            statusLine(snapshot, width: layout.header.width),
            x: layout.header.x,
            y: layout.header.y + 1,
            style: TextStyle(dim: true)
        )
        window.renderDivider(atRow: layout.divider.y, in: buffer.area, buffer: &buffer)
        renderRows(level: level, in: layout.list, buffer: &buffer)
        Scrollbar(total: snapshot.children.count, visible: layout.visibleRows, offset: level.offset)
            .render(column: width - 1, rows: layout.list.y..<(layout.list.y + layout.list.height), buffer: &buffer)

        for (index, line) in layout.pathLines.prefix(layout.path.height).enumerated() {
            let label = index == 0 ? focusedLabel : String(repeating: " ", count: focusedLabel.count)
            buffer.write(
                [Span(label, TextStyle(dim: true)), Span(line)],
                x: layout.path.x,
                y: layout.path.y + index,
                maxWidth: layout.path.width
            )
        }
        if let error = snapshot.errors.first {
            let area = layout.error
            buffer.write(
                [Span("! ", TextStyle(color: .red)), Span(Term.truncate(error, to: max(1, area.width - 2), middle: true))],
                x: area.x,
                y: area.y,
                maxWidth: area.width
            )
        }
        browserHints.render(in: layout.footer, buffer: &buffer)
        return buffer
    }

    private static func renderRows(level: BrowserLevel, in list: Rect, buffer: inout Buffer) {
        let snapshot = level.snapshot
        let upperBound = min(snapshot.children.count, level.offset + list.height)
        guard level.offset < upperBound else {
            let inaccessible = snapshot.inaccessibleCount > 0
            buffer.write(
                inaccessible ? "Folder contents are inaccessible." : "No measurable items.",
                x: list.x,
                y: list.y,
                style: inaccessible ? TextStyle(color: .red) : TextStyle(dim: true),
                maxWidth: list.width
            )
            return
        }
        for (offset, child) in snapshot.children[level.offset..<upperBound].enumerated() {
            let rect = Rect(x: list.x, y: list.y + offset, width: list.width, height: 1)
            renderRow(child, focused: level.offset + offset == level.selected, total: snapshot.total, in: rect, buffer: &buffer)
        }
    }

    static func visibleRowCount(snapshot: FolderSnapshot, selected: Int, width: Int, height: Int) -> Int {
        layout(snapshot: snapshot, selected: selected, width: width, height: height).visibleRows
    }

    static func adjustedOffset(_ offset: Int, selected: Int, count: Int, visibleRows: Int) -> Int {
        guard count > 0 else { return 0 }
        let selection = min(max(0, selected), count - 1)
        var result = min(max(0, offset), max(0, count - visibleRows))
        if selection < result { result = selection }
        if selection >= result + visibleRows { result = selection - visibleRows + 1 }
        return max(0, result)
    }

    private static func focusedChild(_ level: BrowserLevel) -> Child? {
        guard level.snapshot.children.indices.contains(level.selected) else { return nil }
        return level.snapshot.children[level.selected]
    }

    private static func renderRow(_ child: Child, focused: Bool, total: Int64, in rect: Rect, buffer: inout Buffer) {
        let fraction = total > 0 ? Double(child.size) / Double(total) : 0
        let barWidth = min(maximumGaugeWidth, max(minimumGaugeWidth, (rect.width - gaugeReservedWidth) / 3))
        let suffix = child.isDir && !child.isPackage ? "/" : (child.isPackage ? " [package]" : "")
        let partial = child.isPartial ? " !" : ""
        let nameColumn = rect.width - rowPrefixWidth - barWidth
        let nameWidth = max(1, nameColumn - partial.count)
        let name = Term.truncate(URL(fileURLWithPath: child.path).lastPathComponent + suffix, to: nameWidth, middle: true)
        let rowStyle = TextStyle(inverse: focused)
        let sizeStyle = SizeLevel.style(bytes: child.size, focused: focused)
        let gauge = Gauge(fraction: fraction).spans(width: barWidth, filled: sizeStyle).map {
            Span($0.text, TextStyle(color: $0.style.color, dim: $0.style.dim, inverse: focused))
        }
        buffer.write(
            [FocusPointer.span(focused: focused),
             Span(" ", rowStyle),
             Span(Render.sizeCol(child.size), sizeStyle),
             Span(" ", rowStyle)]
                + gauge
                + [Span(" " + Term.pad(name + partial, to: nameColumn), rowStyle)],
            x: rect.x,
            y: rect.y,
            maxWidth: rect.width
        )
    }

    private static func statusLine(_ snapshot: FolderSnapshot, width: Int) -> String {
        var parts = [ByteCount.human(snapshot.total) + " allocated", "\(snapshot.children.count) items"]
        if snapshot.skippedCount > 0 { parts.append("\(snapshot.skippedCount) skipped") }
        if snapshot.inaccessibleCount > 0 { parts.append("\(snapshot.inaccessibleCount) inaccessible") }
        return Term.truncate(parts.joined(separator: "  ·  "), to: width)
    }

    private static func revealInFinder(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-R", path]
        try? process.run()
    }

}

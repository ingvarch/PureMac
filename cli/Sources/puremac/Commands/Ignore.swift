import ArgumentParser
import Foundation
import TerminalUI

struct Ignore: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Protect paths so clean/purge/analyze never touch them.",
        subcommands: [Add.self, Remove.self, List.self],
        defaultSubcommand: List.self
    )

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a path to the ignore list.")
        @Argument(help: "Path to protect.") var path: String
        func run() throws {
            var store = try IgnoreStore(fileURL: AppPaths.ignoreFile)
            let added = try store.add(path)
            let shown = Render.shorten(((path as NSString).expandingTildeInPath as NSString).standardizingPath)
            print(added ? Term.green("✓ Protected ") + shown : Term.dim("Already protected: \(shown)"))
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a path from the ignore list.")
        @Argument(help: "Path to stop protecting.") var path: String
        func run() throws {
            var store = try IgnoreStore(fileURL: AppPaths.ignoreFile)
            let removed = try store.remove(path)
            let shown = Render.shorten(((path as NSString).expandingTildeInPath as NSString).standardizingPath)
            print(removed ? Term.green("✓ Removed ") + shown : Term.yellow("Not in ignore list: \(shown)"))
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show protected paths.")
        static let sheetTitle = "Protected paths"

        func run() throws {
            let store = try IgnoreStore(fileURL: AppPaths.ignoreFile)
            guard !store.roots.isEmpty else {
                print(Term.styled(Self.emptyHint(quoted: true)))
                return
            }
            print(Term.bold("Protected paths:"))
            for line in Self.sheet(roots: store.roots).plainLines(withHeader: false) { print(line) }
        }

        static func emptyHint(quoted: Bool) -> [Span] {
            let quote = quoted ? "`" : ""
            return [
                Span("No protected paths. Add one with " + quote, TextStyle(dim: true)),
                Span("puremac ignore add <path>", TextStyle(color: .cyan)),
                Span(quote + ".", TextStyle(dim: true)),
            ]
        }

        static func sheet(roots: [String]) -> InfoSheet {
            let rows: [InfoRow] = roots.isEmpty
                ? [.message(emptyHint(quoted: false))]
                : roots.sorted().map { .path(Render.shorten($0)) }
            return InfoSheet(title: sheetTitle, subtitle: nil, sections: [InfoSection(title: nil, rows: rows)], footnote: nil)
        }

        static func currentSheet() throws -> InfoSheet {
            sheet(roots: try IgnoreStore(fileURL: AppPaths.ignoreFile).roots)
        }
    }
}

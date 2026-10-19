import ArgumentParser
import Foundation
import TerminalUI

let puremacVersion = "1.1.1"

@main
struct PureMac: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "puremac",
        abstract: "Review caches, clean project artifacts, and explore your storage.",
        discussion: """
        Run puremac to open the interactive workspace. Select individual paths,
        review their sizes, and confirm before permanent cleanup.
        Use --help on any command for script-friendly options.
        """,
        version: puremacVersion,
        subcommands: [Clean.self, Purge.self, Analyze.self, Optimize.self, Ignore.self, Config.self]
    )

    func run() throws {
        guard TerminalSession.isSupported else {
            print(Self.helpMessage())
            return
        }
        try? AppPaths.ensureDefaults()
        try HomeMenu.run()
    }
}

enum HomeMenu {
    static let title = "PureMac"
    static let subtitle = "Your Mac, with room to work.  /  \(puremacVersion)"
    static let exploreIndex = 2
    static let options: [(title: String, detail: String)] = [
        ("Clean caches", "Choose tools and individual paths to remove"),
        ("Project cleanup", "Review dependencies and generated build artifacts"),
        ("Explore storage", "Browse folders and find what takes up space"),
        ("System status", "Inspect memory and available disk space"),
        ("Preferences", "View cleanup settings and configuration paths"),
        ("Protected paths", "View folders excluded from cleanup")
    ]

    static func run() throws {
        var focus = 0
        while let choice = try TerminalMenu.choose(title: title, subtitle: subtitle, options: options, initialSelection: focus) {
            focus = choice
            if let sheet = sheet(forChoice: choice) {
                let session = try TerminalSession()
                defer { session.close() }
                sheet.show(in: session)
                continue
            }
            switch choice {
            case 0:
                guard let category = try TerminalMenu.choose(
                    title: "Clean caches",
                    subtitle: "Scan first. Choose what to remove afterward.",
                    options: [
                        ("All categories", "Developer caches, user junk, AI tools, and Trash"),
                        ("Developer caches", "Package managers and build tools"),
                        ("User junk", "Logs and generated Xcode files"),
                        ("AI tools", "Caches and logs from local AI tools"),
                        ("Trash", "Review items already in the Trash")
                    ]
                ) else { continue }
                let arguments = [[], ["dev"], ["junk"], ["ai"], ["trash"]]
                try Clean.parse(arguments[category]).run()
            case 1: try Purge.parse([]).run()
            case exploreIndex:
                guard try ExploreConfirmation.ask() else { continue }
                try Analyze.parse([]).run()
            default: return
            }
        }
    }

    static func sheet(forChoice choice: Int) -> InfoSheet? {
        switch choice {
        case 3: return InfoSheet.loading(title: Optimize.statusTitle, Optimize.currentStatusSheet)
        case 4: return InfoSheet.loading(title: Config.sheetTitle, Config.currentSheet)
        case 5: return InfoSheet.loading(title: Ignore.List.sheetTitle, Ignore.List.currentSheet)
        default: return nil
        }
    }
}

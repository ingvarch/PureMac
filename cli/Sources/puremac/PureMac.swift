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
        var setupError: Error?
        do { try AppPaths.ensureDefaults() } catch { setupError = error }
        try HomeMenu.run(setupError: setupError)
    }
}

enum HomeMenu {
    static let title = "PureMac"
    static let subtitle = "Your Mac, with room to work.  /  \(puremacVersion)"
    static let projectCleanupIndex = 1
    static let exploreIndex = 2
    static let statusIndex = 3
    static let preferencesIndex = 4
    static let protectedPathsIndex = 5
    static let options: [(title: String, detail: String)] = [
        ("Clean caches", "Choose tools and individual paths to remove"),
        ("Project cleanup", "Review dependencies and generated build artifacts"),
        ("Explore storage", "Browse folders and find what takes up space"),
        ("System status", "Inspect memory and available disk space"),
        ("Preferences", "Change cleanup age, project folders, and protection"),
        ("Protected paths", "Choose paths excluded from cleanup")
    ]

    static func screen(selection: Int, width: Int, height: Int) -> Buffer {
        TerminalMenu.render(
            title: title, subtitle: subtitle, options: options, selection: selection, width: width, height: height
        )
    }

    static func projectCleanupConfirmation(folderCount: Int) -> StartConfirmation? {
        folderCount > 0 ? .projectCleanup(folderCount: folderCount) : nil
    }

    static func noFoldersNotice(width: Int, height: Int) -> Buffer {
        CleanupFlow.infoScreen(
            title: options[projectCleanupIndex].title,
            message: Purge.noFoldersMessage,
            on: screen(selection: projectCleanupIndex, width: width, height: height)
        )
    }

    private static func showNoFoldersNotice() throws {
        let session = try TerminalSession()
        defer { session.close() }
        CleanupFlow.showInfo(on: session) { noFoldersNotice(width: session.width, height: session.height) }
    }

    static func run(setupError: Error?) throws {
        var focus = 0
        while let choice = try TerminalMenu.choose(title: title, subtitle: subtitle, options: options, initialSelection: focus) {
            focus = choice
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
            case projectCleanupIndex:
                let folderCount = try ConfigStore(fileURL: AppPaths.configFile).projectRoots.count
                guard let confirmation = projectCleanupConfirmation(folderCount: folderCount) else {
                    try showNoFoldersNotice()
                    continue
                }
                guard try confirmation.ask() else { continue }
                try Purge.parse([]).run()
            case exploreIndex:
                guard try StartConfirmation.explore.ask() else { continue }
                try Analyze.parse([]).run()
            case statusIndex:
                let session = try TerminalSession()
                defer { session.close() }
                SystemStatusScreen.run(in: session)
            case preferencesIndex:
                let session = try TerminalSession()
                defer { session.close() }
                PreferencesScreen.run(setupError: setupError, in: session)
            case protectedPathsIndex:
                let session = try TerminalSession()
                defer { session.close() }
                PathListEditor.run(.protectedPaths, in: session)
            default: return
            }
        }
    }
}

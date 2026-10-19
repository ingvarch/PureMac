import Foundation
import XCTest
@testable import puremac
import TerminalUI

final class PlainCommandOutputTests: XCTestCase {
    func testConfigPrintsTodaysTextWithDefaultValue() throws {
        try withConfigHome { dir in
            let output = try captureStdout { try Config.parse([]).run() }
            XCTAssertEqual(output, """
            PureMac CLI settings
            Values used when a command-line option is omitted

              purge.older_than_days      7 days  default

            Files
              Settings     \(dir.path)/config.json
              Protected    \(dir.path)/ignore

            Project folders
            \(Purger.defaultRoots.map { "  " + Render.shorten($0) + "\n" }.joined())
            """)
        }
    }

    func testConfigPrintsSavedValue() throws {
        try withConfigHome { dir in
            var store = try ConfigStore(fileURL: AppPaths.configFile)
            try store.set("purge.older_than_days", "14")
            let output = try captureStdout { try Config.parse([]).run() }
            XCTAssertTrue(output.contains("\n  purge.older_than_days      14 days  saved\n"), output)
        }
    }

    func testIgnoreListPrintsTodaysTextWhenEmpty() throws {
        try withConfigHome { _ in
            let output = try captureStdout { try Ignore.List.parse([]).run() }
            XCTAssertEqual(output, "No protected paths. Add one with `puremac ignore add <path>`.\n")
        }
    }

    func testIgnoreListHintHasACyanCommandWhenColorsAreOn() {
        let styled = Term.styled(Ignore.List.emptyHint(quoted: true), colors: true)
        XCTAssertTrue(styled.contains("\u{1B}[0m\u{1B}[36mpuremac ignore add <path>"), styled)
    }

    func testIgnoreListKeepsZeroWidthCharactersInPaths() throws {
        try withConfigHome { _ in
            var store = try IgnoreStore(fileURL: AppPaths.ignoreFile)
            _ = try store.add("/tmp/puremac-a\u{200B}b")
            let output = try captureStdout { try Ignore.List.parse([]).run() }
            XCTAssertEqual(output, "Protected paths:\n  /tmp/puremac-a\u{200B}b\n")
        }
    }

    func testIgnoreListPrintsSortedPaths() throws {
        try withConfigHome { _ in
            var store = try IgnoreStore(fileURL: AppPaths.ignoreFile)
            _ = try store.add("/tmp/puremac-b")
            _ = try store.add("/tmp/puremac-a")
            let output = try captureStdout { try Ignore.List.parse([]).run() }
            XCTAssertEqual(output, "Protected paths:\n  /tmp/puremac-a\n  /tmp/puremac-b\n")
        }
    }
}

final class PreferencesSheetTests: XCTestCase {
    private let dim = TextStyle(dim: true)

    func testPreferencesSheetListsKeysWithValueAndNote() throws {
        try withConfigHome { dir in
            var store = try ConfigStore(fileURL: AppPaths.configFile)
            var sheet = Config.sheet(store: store)
            XCTAssertEqual(sheet.title, "PureMac CLI settings")
            XCTAssertEqual(sheet.subtitle, "Values used when a command-line option is omitted")
            XCTAssertEqual(sheet.sections.map(\.title), [nil, "Files", "Project folders"])
            guard case .metric("purge.older_than_days", let value, let note) = sheet.sections[0].rows[0] else { return XCTFail("key row") }
            XCTAssertEqual(value, [Span("7 days")])
            XCTAssertEqual(note, Span("default", dim))

            try store.set("purge.older_than_days", "14")
            sheet = Config.sheet(store: store)
            guard case .metric(_, let saved, let savedNote) = sheet.sections[0].rows[0] else { return XCTFail("key row") }
            XCTAssertEqual(saved, [Span("14 days")])
            XCTAssertEqual(savedNote, Span("saved", TextStyle(color: .cyan)))

            XCTAssertEqual(sheet.sections[1].rows.count, 2)
            guard case .metric("Settings", let settings, nil) = sheet.sections[1].rows[0] else { return XCTFail("settings row") }
            XCTAssertEqual(settings, [Span("\(dir.path)/config.json")])
        }
    }

    func testProtectedPathsSheetListsSortedPaths() {
        let sheet = Ignore.List.sheet(roots: ["/tmp/b", "/tmp/a"])
        XCTAssertEqual(sheet.title, "Protected paths")
        XCTAssertNil(sheet.subtitle)
        XCTAssertEqual(sheet.sections.count, 1)
        XCTAssertEqual(sheet.sections[0].rows.count, 2)
        guard case .path(let first) = sheet.sections[0].rows[0] else { return XCTFail("path row") }
        XCTAssertEqual(first, "/tmp/a")
    }

    func testProtectedPathsSheetWithoutPathsShowsTheHintWithACyanCommand() {
        let sheet = Ignore.List.sheet(roots: [])
        guard case .message(let spans) = sheet.sections[0].rows[0] else { return XCTFail("hint row") }
        XCTAssertEqual(spans.map(\.text).joined(), "No protected paths. Add one with puremac ignore add <path>.")
        XCTAssertEqual(spans.filter { $0.style.color == .cyan }.map(\.text), ["puremac ignore add <path>"])
        XCTAssertEqual(sheet.sections[0].rows.count, 1)
    }

    func testHomeMenuOpensSheetsOnlyForStatusPreferencesAndProtectedPaths() throws {
        try withConfigHome { _ in
            for choice in 0...2 { XCTAssertNil(HomeMenu.sheet(forChoice: choice), "\(choice)") }
            XCTAssertEqual(HomeMenu.sheet(forChoice: 3)?.title, "Mac status")
            XCTAssertEqual(HomeMenu.sheet(forChoice: 4)?.title, "PureMac CLI settings")
            XCTAssertEqual(HomeMenu.sheet(forChoice: 5)?.title, "Protected paths")
            XCTAssertNil(HomeMenu.sheet(forChoice: 6))
        }
    }

    func testHomeMenuShowsAStoreErrorAsARedRowInsteadOfThrowing() throws {
        try withConfigHome { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("[]".utf8).write(to: AppPaths.configFile)
            try Data("relative/path\n".utf8).write(to: AppPaths.ignoreFile)
            for (choice, title) in [(4, "PureMac CLI settings"), (5, "Protected paths")] {
                let sheet = try XCTUnwrap(HomeMenu.sheet(forChoice: choice))
                XCTAssertEqual(sheet.title, title)
                guard case .message(let spans) = sheet.sections[0].rows[0] else { return XCTFail("error row") }
                XCTAssertEqual(spans.first?.style, TextStyle(color: .red))
            }
        }
    }
}

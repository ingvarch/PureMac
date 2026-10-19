import Foundation
import XCTest
@testable import puremac
import TerminalUI

private func write(_ text: String, to file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
}

final class ConfigSettingsTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("puremac/config.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("puremac-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingFileGivesTheDefaults() throws {
        let store = try ConfigStore(fileURL: file)
        XCTAssertEqual(store.olderThanDays, 7)
        XCTAssertEqual(store.projectRoots, Purger.defaultRoots)
    }

    func testOldFileWithOnlyTheDaysKeyStillLoads() throws {
        try write(#"{"purge.older_than_days": "14"}"#, to: file)
        let store = try ConfigStore(fileURL: file)
        XCTAssertEqual(store.olderThanDays, 14)
        XCTAssertEqual(store.projectRoots, Purger.defaultRoots)
    }

    func testNewFileLoadsTheRootsInOrder() throws {
        try write(#"{"purge.older_than_days": "30", "purge.roots": ["/tmp/b", "/tmp/a"]}"#, to: file)
        let store = try ConfigStore(fileURL: file)
        XCTAssertEqual(store.olderThanDays, 30)
        XCTAssertEqual(store.projectRoots, ["/tmp/b", "/tmp/a"])
    }

    func testWrongTypesAndRootsAreInvalidConfigFiles() throws {
        let bad = [
            #"{"purge.roots": "/tmp/a"}"#,
            #"{"purge.roots": ["/tmp/a", 3]}"#,
            #"{"purge.roots": ["relative/path"]}"#,
            #"{"purge.roots": [""]}"#,
            #"{"purge.older_than_days": 14}"#,
            "[]",
        ]
        for text in bad {
            try write(text, to: file)
            XCTAssertThrowsError(try ConfigStore(fileURL: file), text) { error in
                guard case StoreError.invalidConfigFile = error else { return XCTFail("\(text): \(error)") }
            }
        }
    }

    func testBadDaysValuesAndUnknownKeysKeepTheirValueErrors() throws {
        let bad = [
            (#"{"purge.older_than_days": "0"}"#, "invalidConfigValue"),
            (#"{"purge.older_than_days": "x", "purge.roots": []}"#, "invalidConfigValue"),
            (#"{"other": "1"}"#, "unknownConfigKey"),
        ]
        for (text, name) in bad {
            try write(text, to: file)
            XCTAssertThrowsError(try ConfigStore(fileURL: file), text) { error in
                XCTAssertTrue("\(error)".hasPrefix(name), "\(text): \(error)")
            }
        }
    }

    func testDaysWithSurroundingWhitespaceAreStoredNormalized() throws {
        try write(#"{"purge.older_than_days": " 14\n"}"#, to: file)
        XCTAssertEqual(try ConfigStore(fileURL: file).olderThanDays, 14)
    }

    func testEmptyRootsListIsKeptAndNotReplacedByDefaults() throws {
        try write(#"{"purge.roots": []}"#, to: file)
        XCTAssertEqual(try ConfigStore(fileURL: file).projectRoots, [])
    }

    func testRootsRoundTripKeepOrderAndSurviveASetOfTheDays() throws {
        var store = try ConfigStore(fileURL: file)
        try store.setProjectRoots(["/tmp/z", "/tmp/a/../a", "/tmp/m/"])
        XCTAssertEqual(store.projectRoots, ["/tmp/z", "/tmp/a", "/tmp/m"])

        var reloaded = try ConfigStore(fileURL: file)
        XCTAssertEqual(reloaded.projectRoots, ["/tmp/z", "/tmp/a", "/tmp/m"])
        try reloaded.set("purge.older_than_days", "90")

        let again = try ConfigStore(fileURL: file)
        XCTAssertEqual(again.olderThanDays, 90)
        XCTAssertEqual(again.projectRoots, ["/tmp/z", "/tmp/a", "/tmp/m"])
    }

    func testSavedFileHasSortedKeysAndIsPrettyPrinted() throws {
        var store = try ConfigStore(fileURL: file)
        try store.set("purge.older_than_days", "14")
        try store.setProjectRoots(["/tmp/a"])
        let text = try String(contentsOf: file, encoding: .utf8)
        let days = try XCTUnwrap(text.range(of: "purge.older_than_days"))
        let roots = try XCTUnwrap(text.range(of: "purge.roots"))
        XCTAssertLessThan(days.lowerBound, roots.lowerBound)
        XCTAssertTrue(text.contains("\n  \""), text)
    }

    func testRelativeRootsAreRejectedAndNothingIsSaved() throws {
        var store = try ConfigStore(fileURL: file)
        XCTAssertThrowsError(try store.setProjectRoots(["relative"])) { error in
            guard case StoreError.invalidProjectRoot("relative") = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(store.projectRoots, Purger.defaultRoots)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testInvalidProjectRootMessageNamesTheFolder() {
        XCTAssertEqual(
            StoreError.invalidProjectRoot("relative").errorDescription,
            "Project folders must be absolute paths: relative"
        )
    }

    func testRootsAreNotSettableThroughConfigSet() {
        XCTAssertThrowsError(try Config.parse(["set", "purge.roots", "/tmp/a"]))
    }

    func testEnsureDefaultsCreatesBothFilesWithDefaults() throws {
        let config = directory.appendingPathComponent("puremac/config.json")
        let ignore = directory.appendingPathComponent("puremac/ignore")
        try AppPaths.ensureDefaults(configFile: config, ignoreFile: ignore)

        let store = try ConfigStore(fileURL: config)
        XCTAssertEqual(store.olderThanDays, 7)
        XCTAssertEqual(store.projectRoots, Purger.defaultRoots)
        let saved = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(saved.contains("purge.roots") && saved.contains("purge.older_than_days"), saved)
        XCTAssertEqual(try String(contentsOf: ignore, encoding: .utf8), "")
        XCTAssertEqual(try IgnoreStore(fileURL: ignore).roots, [])
    }

    func testEnsureDefaultsNeverOverwritesExistingFiles() throws {
        let config = directory.appendingPathComponent("puremac/config.json")
        let ignore = directory.appendingPathComponent("puremac/ignore")
        try write(#"{"purge.older_than_days": "14"}"#, to: config)
        try write("/tmp/keep\n", to: ignore)

        try AppPaths.ensureDefaults(configFile: config, ignoreFile: ignore)
        try AppPaths.ensureDefaults(configFile: config, ignoreFile: ignore)

        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), #"{"purge.older_than_days": "14"}"#)
        XCTAssertEqual(try String(contentsOf: ignore, encoding: .utf8), "/tmp/keep\n")
    }

    func testEnsureDefaultsFillsOnlyTheMissingFile() throws {
        let config = directory.appendingPathComponent("puremac/config.json")
        let ignore = directory.appendingPathComponent("puremac/ignore")
        try write("/tmp/keep\n", to: ignore)
        try AppPaths.ensureDefaults(configFile: config, ignoreFile: ignore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.path))
        XCTAssertEqual(try String(contentsOf: ignore, encoding: .utf8), "/tmp/keep\n")
    }

    func testEnsureDefaultsLeavesAnInvalidConfigFileAlone() throws {
        let config = directory.appendingPathComponent("puremac/config.json")
        let ignore = directory.appendingPathComponent("puremac/ignore")
        try write("[]", to: config)
        try AppPaths.ensureDefaults(configFile: config, ignoreFile: ignore)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "[]")
    }

    func testEnsureDefaultsCreatesTheIgnoreFileEvenWhenTheConfigFileFails() throws {
        let blocker = directory.appendingPathComponent("blocker")
        try write("x", to: blocker)
        let config = blocker.appendingPathComponent("config.json")
        let ignore = directory.appendingPathComponent("puremac/ignore")
        XCTAssertThrowsError(try AppPaths.ensureDefaults(configFile: config, ignoreFile: ignore))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ignore.path))
    }

    func testEnsureDefaultsCreatesTheConfigFileEvenWhenTheIgnoreFileFails() throws {
        let blocker = directory.appendingPathComponent("blocker")
        try write("x", to: blocker)
        let config = directory.appendingPathComponent("puremac/config.json")
        let ignore = blocker.appendingPathComponent("ignore")
        XCTAssertThrowsError(try AppPaths.ensureDefaults(configFile: config, ignoreFile: ignore))
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.path))
    }

    func testTheWorkspaceEntryPointCreatesNothingWithoutATerminal() throws {
        try withConfigHome { dir in
            _ = try captureStdout { try PureMac.parse([]).run() }
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        }
    }

    func testPurgeWithAnEmptyFolderListSaysSoAndDoesNotScan() throws {
        try withConfigHome { _ in
            var store = try ConfigStore(fileURL: AppPaths.configFile)
            try store.setProjectRoots([])
            let output = try captureStdout { try Purge.parse(["--dry-run"]).run() }
            XCTAssertEqual(output, Term.dim(Purge.noFoldersMessage) + "\n")
        }
    }

    func testOtherCommandsNeverCreateTheDefaultFiles() throws {
        let scanned = directory.appendingPathComponent("scanned")
        try FileManager.default.createDirectory(at: scanned, withIntermediateDirectories: true)
        try withConfigHome { dir in
            _ = try captureStdout { try Config.parse([]).run() }
            _ = try captureStdout { try Ignore.List.parse([]).run() }
            _ = try captureStdout { try Purge.parse([scanned.path, "--json"]).run() }
            _ = try captureStdout { try Purge.parse([scanned.path, "--dry-run"]).run() }
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        }
    }

    func testPurgeWithoutPathsScansTheConfiguredRoots() throws {
        try withConfigHome { _ in
            var store = try ConfigStore(fileURL: AppPaths.configFile)
            try store.setProjectRoots(["/tmp/one", "/tmp/two"])
            XCTAssertEqual(try Purge.parse([]).resolvedRoots(), ["/tmp/one", "/tmp/two"])
        }
    }

    func testPurgeWithoutPathsFallsBackToTheDefaultsWithoutAFile() throws {
        try withConfigHome { _ in
            XCTAssertEqual(try Purge.parse([]).resolvedRoots(), Purger.defaultRoots)
        }
    }

    func testPurgeWithExplicitPathsIgnoresTheConfigFile() throws {
        try withConfigHome { _ in
            try write("[]", to: AppPaths.configFile)
            let explicit = directory.appendingPathComponent("explicit")
            try FileManager.default.createDirectory(at: explicit, withIntermediateDirectories: true)
            let roots = try Purge.parse([explicit.path + "/../explicit"]).resolvedRoots()
            XCTAssertEqual(roots, [Safety.absolutePath(explicit.path)])
        }
    }

    func testConfigPlainOutputListsProjectFoldersAfterTheFiles() throws {
        try withConfigHome { dir in
            var store = try ConfigStore(fileURL: AppPaths.configFile)
            try store.setProjectRoots(["\(Safety.home)/Work", "/tmp/other"])
            let output = try captureStdout { try Config.parse([]).run() }
            XCTAssertEqual(output, """
            PureMac CLI settings
            Values used when a command-line option is omitted

              purge.older_than_days      7 days  default

            Files
              Settings     \(dir.path)/config.json
              Protected    \(dir.path)/ignore

            Project folders
              ~/Work
              /tmp/other

            """)
        }
    }

    func testAFileHoldingTheDefaultDaysShowsDefault() throws {
        try withConfigHome { _ in
            var store = try ConfigStore(fileURL: AppPaths.configFile)
            try store.set("purge.older_than_days", "7")
            let output = try captureStdout { try Config.parse([]).run() }
            XCTAssertTrue(output.contains("\n  purge.older_than_days      7 days  default\n"), output)
            try store.set("purge.older_than_days", "8")
            let changed = try captureStdout { try Config.parse([]).run() }
            XCTAssertTrue(changed.contains("8 days  saved"), changed)
        }
    }

    func testSavedFileKeepsSlashesUnescaped() throws {
        var store = try ConfigStore(fileURL: file)
        try store.setProjectRoots(["/Users/me/Projects"])
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("\"/Users/me/Projects\""), text)
        XCTAssertFalse(text.contains("\\/"), text)
        XCTAssertEqual(try ConfigStore(fileURL: file).projectRoots, ["/Users/me/Projects"])
    }

    func testDefaultFileKeepsSlashesUnescaped() throws {
        let text = String(decoding: try ConfigStore.defaultFileData(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"\(Safety.home)/Projects\""), text)
        XCTAssertFalse(text.contains("\\/"), text)
    }
}

import Foundation
import XCTest
@testable import puremac

final class ScanProgressTests: XCTestCase {
    func testFullscreenCleanupWritesNoScanProgress() {
        XCTAssertEqual(ScanProgress.forMode(.fullscreen), .silent)
        for mode in [CleanupCommandMode.plain, .forced, .reportOnly] {
            XCTAssertEqual(ScanProgress.forMode(mode), .stderr)
        }
    }

    func testSilentScanWritesNothingToStderrAndDefaultKeepsTheProgressLine() throws {
        let silent = try captureStderr { _ = CategoryScanner.scan(categoryID: "none", title: "None", ignore: ignore(), progress: .silent) }
        XCTAssertEqual(silent, "")
        let verbose = try captureStderr { _ = CategoryScanner.scan(categoryID: "none", title: "None", ignore: ignore()) }
        XCTAssertTrue(verbose.hasPrefix("  scanning None…\r"))
    }

    func testCatalogScanReturnsGroupsSizesAndSelection() throws {
        let dir = try tempDir()
        _ = try makeFile("\(dir)/cache-a/data", bytes: 8192)
        try FileManager.default.createDirectory(atPath: "\(dir)/cache-b", withIntermediateDirectories: true)
        let targets = [
            Target(tool: "Tool A", paths: ["\(dir)/cache-a"], selectedByDefault: false),
            Target(tool: "Tool B", paths: ["\(dir)/cache-b"]),
            Target(tool: "Tool C", paths: ["\(dir)/missing"])
        ]
        let groups = CategoryScanner.scanCatalog(targets: targets, ignore: ignore(), isCancelled: { false })
        XCTAssertEqual(groups.map(\.tool), ["Tool A"])
        let item = try XCTUnwrap(groups.first?.items.first)
        XCTAssertEqual(item.path, "\(dir)/cache-a")
        XCTAssertGreaterThanOrEqual(item.sizeBytes, 8192)
        XCTAssertFalse(item.selected)
    }

    func testCatalogScanOfContentsTargetListsChildren() throws {
        let dir = try tempDir()
        _ = try makeFile("\(dir)/logs/one/data", bytes: 8192)
        _ = try makeFile("\(dir)/logs/two/data", bytes: 8192)
        let groups = CategoryScanner.scanCatalog(
            targets: [Target(tool: "Logs", paths: ["\(dir)/logs"], contents: true)], ignore: ignore(), isCancelled: { false }
        )
        XCTAssertEqual(groups.first?.items.map(\.path).sorted(), ["\(dir)/logs/one", "\(dir)/logs/two"])
        XCTAssertTrue(groups.first?.items.allSatisfy(\.selected) ?? false)
    }

    func testCancelledCatalogScanReturnsNoGroups() throws {
        let dir = try tempDir()
        _ = try makeFile("\(dir)/cache/data", bytes: 8192)
        let groups = CategoryScanner.scanCatalog(
            targets: [Target(tool: "Tool", paths: ["\(dir)/cache"])], ignore: ignore(), isCancelled: { true }
        )
        XCTAssertTrue(groups.isEmpty)
    }

    func testTrashScanReturnsOneGroupPerRootWithItems() throws {
        let dir = try tempDir()
        _ = try makeFile("\(dir)/trash/old/data", bytes: 8192)
        let groups = CategoryScanner.scanTrash(
            roots: ["\(dir)/trash", "\(dir)/no-trash"], ignore: ignore(), isCancelled: { false }
        )
        XCTAssertEqual(groups.map(\.tool), ["Trash"])
        XCTAssertEqual(groups.first?.items.map(\.path), ["\(dir)/trash/old"])
        XCTAssertTrue(groups.first?.items.allSatisfy(\.selected) ?? false)
    }

    func testCancelledTrashScanReturnsNoGroups() throws {
        let dir = try tempDir()
        _ = try makeFile("\(dir)/trash/old/data", bytes: 8192)
        XCTAssertTrue(CategoryScanner.scanTrash(roots: ["\(dir)/trash"], ignore: ignore(), isCancelled: { true }).isEmpty)
    }

    func testDefaultScanOfAnUnknownCategoryIsEmpty() {
        let scan = CategoryScanner.scan(categoryID: "none", title: "None", ignore: ignore(), progress: .silent)
        XCTAssertEqual(scan.id, "none")
        XCTAssertEqual(scan.title, "None")
        XCTAssertTrue(scan.groups.isEmpty)
    }

    private func ignore() -> IgnoreStore {
        try! IgnoreStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("scan-progress-\(UUID().uuidString)"))
    }

    private func tempDir() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-progress-dir-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    private func makeFile(_ path: String, bytes: Int) throws -> String {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try Data(repeating: 1, count: bytes).write(to: URL(fileURLWithPath: path))
        return path
    }
}

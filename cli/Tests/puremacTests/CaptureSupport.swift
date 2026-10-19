import Foundation
@testable import puremac

func capture(_ descriptor: Int32, _ body: () throws -> Void) throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: url) }
    let handle = try FileHandle(forWritingTo: url)
    fflush(stdout)
    let saved = dup(descriptor)
    dup2(handle.fileDescriptor, descriptor)
    defer {
        fflush(stdout)
        dup2(saved, descriptor)
        close(saved)
    }
    try body()
    fflush(stdout)
    try handle.close()
    return String(decoding: try Data(contentsOf: url), as: UTF8.self)
}

func captureStdout(_ body: () throws -> Void) throws -> String { try capture(STDOUT_FILENO, body) }
func captureStderr(_ body: () throws -> Void) throws -> String { try capture(STDERR_FILENO, body) }

extension InteractiveReviewModel {
    static func selected(_ categories: [CategoryScan], selecting indices: [Int], query: String = "") -> InteractiveReviewModel {
        var model = InteractiveReviewModel(categories: categories)
        if !query.isEmpty { model.updateQuery(query) }
        var position = 0
        for index in indices {
            model.move(index - position)
            position = index
            model.toggleFocused()
        }
        return model
    }
}

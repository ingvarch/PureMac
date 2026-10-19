import XCTest
@testable import TerminalUI

final class BackgroundWorkTests: XCTestCase {
    private let wait: DispatchTimeInterval = .seconds(5)

    func testRedrawsUntilWorkFinishesAndTickIncreases() {
        let release = DispatchSemaphore(value: 0)
        var ticks: [Int] = []
        var reads = 0

        let result = BackgroundWork.run(
            progress: 0,
            draw: { tick, _ in ticks.append(tick) },
            readKey: { _ in
                reads += 1
                if reads == 5 { release.signal() }
                return nil
            },
            onKey: { _, _ in },
            work: { _, _ in
                _ = release.wait(timeout: .now() + self.wait)
                return "done"
            }
        )

        XCTAssertEqual(result, "done")
        XCTAssertGreaterThanOrEqual(ticks.count, 5)
        XCTAssertEqual(ticks, Array(0..<ticks.count))
    }

    func testReadKeyGetsTheRedrawIntervalAsTimeout() {
        let release = DispatchSemaphore(value: 0)
        var timeouts: [Int] = []

        _ = BackgroundWork.run(
            progress: 0,
            draw: { _, _ in },
            readKey: { timeout in
                timeouts.append(timeout)
                release.signal()
                return nil
            },
            onKey: { _, _ in },
            work: { _, _ in release.wait(timeout: .now() + self.wait) }
        )

        XCTAssertEqual(timeouts.first, BackgroundWork.redrawIntervalMilliseconds)
        XCTAssertEqual(BackgroundWork.redrawIntervalMilliseconds, 80)
    }

    func testKeysReachTheHandler() {
        let release = DispatchSemaphore(value: 0)
        var script: [TerminalKey?] = [nil, .down, nil, .character("x")]
        var received: [TerminalKey] = []

        _ = BackgroundWork.run(
            progress: 0,
            draw: { _, _ in },
            readKey: { _ in
                guard !script.isEmpty else { release.signal(); return nil }
                return script.removeFirst()
            },
            onKey: { key, _ in received.append(key) },
            work: { _, _ in release.wait(timeout: .now() + self.wait) }
        )

        XCTAssertEqual(received, [.down, .character("x")])
    }

    func testHandlerCanCancelAndWorkSeesTheFlag() {
        var sent = false

        let result = BackgroundWork.run(
            progress: 0,
            draw: { _, _ in },
            readKey: { _ in
                defer { sent = true }
                return sent ? nil : .escape
            },
            onKey: { key, cancel in if key == .escape { cancel.cancel() } },
            work: { _, cancel in
                let deadline = Date().addingTimeInterval(5)
                while !cancel.isCancelled && Date() < deadline { usleep(1000) }
                return cancel.isCancelled ? "cancelled" : "timeout"
            }
        )

        XCTAssertEqual(result, "cancelled")
    }

    func testProgressFromWorkReachesDraw() {
        let release = DispatchSemaphore(value: 0)
        var lastDrawn = 0

        let result = BackgroundWork.run(
            progress: 0,
            draw: { _, progress in lastDrawn = progress },
            readKey: { _ in
                if lastDrawn == 7 { release.signal() }
                return nil
            },
            onKey: { _, _ in },
            work: { progress, _ in
                progress.set(7)
                _ = release.wait(timeout: .now() + self.wait)
                return progress.value
            }
        )

        XCTAssertEqual(lastDrawn, 7)
        XCTAssertEqual(result, 7)
    }

    func testCancelFlagStartsClear() {
        let flag = CancelFlag()
        XCTAssertFalse(flag.isCancelled)
        flag.cancel()
        XCTAssertTrue(flag.isCancelled)
    }

    func testWorkReturnsWithoutAnyRedrawNeed() {
        let result = BackgroundWork.run(
            progress: 0, draw: { _, _ in }, readKey: { _ in nil }, onKey: { _, _ in },
            work: { _, _ in 42 }
        )
        XCTAssertEqual(result, 42)
    }
}

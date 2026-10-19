import Foundation

public final class WorkProgress<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Value

    public init(_ initial: Value) {
        current = initial
    }

    public var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func set(_ newValue: Value) {
        lock.lock()
        current = newValue
        lock.unlock()
    }
}

public final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

enum BackgroundWork {
    static let redrawIntervalMilliseconds = 80

    static func run<State, Output>(
        progress initial: State,
        draw: (_ tick: Int, _ progress: State) -> Void,
        readKey: (_ timeoutMilliseconds: Int) -> TerminalKey?,
        onKey: (TerminalKey, CancelFlag) -> Void,
        work: @escaping (WorkProgress<State>, CancelFlag) -> Output
    ) -> Output {
        let progress = WorkProgress(initial)
        let cancel = CancelFlag()
        let outcome = WorkProgress<Output?>(nil)

        DispatchQueue.global().async {
            outcome.set(work(progress, cancel))
        }

        var tick = 0
        while outcome.value == nil {
            draw(tick, progress.value)
            if let key = readKey(redrawIntervalMilliseconds) {
                onKey(key, cancel)
            }
            tick += 1
        }
        return outcome.value!
    }
}

extension TerminalSession {
    public func runWithSpinner<State, Output>(
        progress initial: State,
        render: (_ tick: Int, _ progress: State) -> Buffer,
        onKey: (TerminalKey, CancelFlag) -> Void = { _, _ in },
        work: @escaping (WorkProgress<State>, CancelFlag) -> Output
    ) -> Output {
        BackgroundWork.run(
            progress: initial,
            draw: { tick, progress in draw(render(tick, progress)) },
            readKey: { readKey(timeoutMilliseconds: $0) },
            onKey: onKey,
            work: work
        )
    }
}

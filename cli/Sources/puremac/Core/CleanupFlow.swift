import ArgumentParser
import TerminalUI

enum CleanupFlowResult {
    case nothingFound
    case cancelled
    case finished(CleanOutcome)
}

struct RemovalProgress {
    let position: Int
    let count: Int
    let path: String

    init(index: Int, count: Int, path: String) {
        position = index + 1
        self.count = count
        self.path = path
    }
}

enum CleanupFlow {
    private static let removingMaxContentWidth = 60

    struct Labels {
        let scanning: String
        let empty: String
        let reviewTitle: String
        let noun: String
    }

    static func run(
        labels: Labels,
        ignore: IgnoreStore,
        scan: () -> [CategoryScan]
    ) throws -> CleanupFlowResult {
        let session = try TerminalSession()
        defer { session.close() }

        session.draw(scanningScreen(labels: labels, width: session.width, height: session.height))
        let categories = scan()
        guard !categories.isEmpty else {
            session.draw(emptyScreen(labels: labels, width: session.width, height: session.height))
            while !closesInfoDialog(session.readKey()) {}
            return .nothingFound
        }

        guard let review = InteractiveReview.select(
            categories, session: session, title: labels.reviewTitle, noun: labels.noun
        ) else { return .cancelled }

        let items = review.selectedResult().flatMap { $0.selectedItems }
        let outcome = session.runWithSpinner(
            progress: RemovalProgress(index: 0, count: items.count, path: items.first?.path ?? ""),
            render: { tick, progress in
                removingScreen(
                    review: review, labels: labels, progress: progress, tick: tick,
                    width: session.width, height: session.height
                )
            },
            work: { progress, _ in
                Cleaner.remove(items, ignore: ignore, dryRun: false) { index, count, item in
                    progress.set(RemovalProgress(index: index, count: count, path: item.path))
                }
            }
        )
        session.draw(resultScreen(outcome: outcome, review: review, labels: labels, width: session.width, height: session.height))
        while !closesInfoDialog(session.readKey()) {}
        return .finished(outcome)
    }

    static func finish(_ result: CleanupFlowResult, labels: Labels) throws {
        switch result {
        case .nothingFound:
            print(Term.green(labels.empty))
        case .cancelled:
            print(Term.dim("Cancelled. Nothing removed."))
        case .finished(let outcome):
            Render.cleanupSummary(outcome, dryRun: false)
            if outcome.hadFailures { throw ExitCode.failure }
        }
    }

    static func closesInfoDialog(_ key: TerminalKey) -> Bool {
        switch key {
        case .enter, .escape: return true
        case .character(let character): return character.lowercased() == "q"
        default: return false
        }
    }

    static func scanningScreen(labels: Labels, width: Int, height: Int) -> Buffer {
        StatusScreen.render(
            title: "PureMac",
            message: labels.scanning,
            detail: nil,
            hint: StatusScreen.cancelHint,
            width: width,
            height: height
        )
    }

    static func emptyScreen(labels: Labels, width: Int, height: Int) -> Buffer {
        let dialog = Dialog(
            title: "Nothing to clean",
            message: [Span(labels.empty)],
            buttons: [DialogButton("OK")],
            focusedButton: 0
        )
        return StatusScreen.overlay(
            dialog,
            on: scanningScreen(labels: labels, width: width, height: height),
            tooSmallExitHint: closeHint
        )
    }

    static func removingScreen(
        review: InteractiveReviewModel, labels: Labels, progress: RemovalProgress, tick: Int, width: Int, height: Int
    ) -> Buffer {
        let area = Rect(x: 0, y: 0, width: width, height: height)
        return StatusScreen.overlay(
            removingDialog(noun: labels.noun, progress: progress, tick: tick, area: area),
            on: selectionScreen(review, labels: labels, width: width, height: height),
            tooSmallExitHint: "Removing…"
        )
    }

    static func resultScreen(outcome: CleanOutcome, review: InteractiveReviewModel, labels: Labels, width: Int, height: Int) -> Buffer {
        StatusScreen.overlay(
            resultDialog(outcome, area: Rect(x: 0, y: 0, width: width, height: height)),
            on: selectionScreen(review, labels: labels, width: width, height: height),
            tooSmallExitHint: closeHint
        )
    }

    static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    static func removingDialog(noun: String, progress: RemovalProgress, tick: Int, area: Rect) -> Dialog {
        let rowWidth = min(removingMaxContentWidth, Dialog.maxContentWidth(in: area))
        let current = Term.truncate(
            Spinner.frame(tick: tick) + " " + Render.shorten(progress.path), to: rowWidth, middle: true
        )
        return Dialog(
            title: "Removing \(counted(progress.count, noun))…",
            titleStyle: StatusScreen.warningTitle,
            borderStyle: StatusScreen.warningBorder,
            message: [
                Span(Term.pad(current, to: rowWidth)),
                Span("\(progress.position) of \(progress.count)", TextStyle(dim: true))
            ],
            messageAlignment: .leading
        )
    }

    private static let closeHint = "Enter close"

    private static func resultDialog(_ outcome: CleanOutcome, area: Rect) -> Dialog {
        var message = [Span(ByteCount.human(outcome.freedBytes) + Render.removedDetail(outcome))]
        if !outcome.skipped.isEmpty {
            message.append(Span(Render.skippedLabel(outcome) + Render.skippedNote, TextStyle(color: .yellow)))
        }
        if !outcome.failed.isEmpty {
            let red = TextStyle(color: .red)
            message.append(Span(Render.failedLabel(outcome), red))
            let rowWidth = Dialog.maxContentWidth(in: area)
            message += outcome.failed.prefix(3).map {
                Span(Term.truncate("! " + Render.shorten($0.path), to: rowWidth, middle: true), red)
            }
        }
        return Dialog(
            title: Render.cleanupCompleteTitle,
            titleStyle: TextStyle(color: .green, bold: true),
            message: message,
            buttons: [DialogButton("Done")],
            focusedButton: 0
        )
    }

    private static func selectionScreen(_ review: InteractiveReviewModel, labels: Labels, width: Int, height: Int) -> Buffer {
        InteractiveReview.render(
            model: review,
            title: labels.reviewTitle,
            noun: labels.noun,
            width: width,
            height: height
        )
    }
}

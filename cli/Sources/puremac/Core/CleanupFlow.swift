import ArgumentParser
import TerminalUI

enum CleanupFlowResult {
    case nothingFound
    case cancelled
    case finished(CleanOutcome)
}

enum CleanupFlow {
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
        session.draw(removingScreen(review: review, labels: labels, width: session.width, height: session.height))
        let outcome = Cleaner.remove(items, ignore: ignore, dryRun: false)
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

    static func removingScreen(review: InteractiveReviewModel, labels: Labels, width: Int, height: Int) -> Buffer {
        let dialog = removingDialog(count: review.selectedCount, total: review.selectedBytes, noun: labels.noun)
        return StatusScreen.overlay(
            dialog,
            on: finalReview(review, labels: labels, width: width, height: height),
            tooSmallExitHint: "Removing…"
        )
    }

    static func resultScreen(outcome: CleanOutcome, review: InteractiveReviewModel, labels: Labels, width: Int, height: Int) -> Buffer {
        StatusScreen.overlay(
            resultDialog(outcome, area: Rect(x: 0, y: 0, width: width, height: height)),
            on: finalReview(review, labels: labels, width: width, height: height),
            tooSmallExitHint: closeHint
        )
    }

    static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    static func removingDialog(count: Int, total: Int64, noun: String) -> Dialog {
        Dialog(
            title: "Removing \(counted(count, noun))…",
            titleStyle: StatusScreen.warningTitle,
            borderStyle: StatusScreen.warningBorder,
            message: [Span(ByteCount.human(total))]
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

    private static func finalReview(_ review: InteractiveReviewModel, labels: Labels, width: Int, height: Int) -> Buffer {
        InteractiveReview.render(
            model: review,
            title: labels.reviewTitle,
            noun: labels.noun,
            width: width,
            height: height
        )
    }
}

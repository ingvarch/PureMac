public struct Gauge {
    public var fraction: Double

    public init(fraction: Double) {
        self.fraction = fraction
    }

    public func spans(width: Int) -> [Span] {
        let filled = Term.filledCount(fraction: fraction, width: width)
        return [
            Span(String(repeating: "█", count: filled)),
            Span(String(repeating: "░", count: max(0, width) - filled), TextStyle(dim: true))
        ].filter { !$0.text.isEmpty }
    }
}

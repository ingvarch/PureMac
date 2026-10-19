import Darwin
import Foundation

public enum Term {
    private static let localeConfigured: Void = {
        setlocale(LC_CTYPE, "")
    }()

    public static var colorEnabled: Bool {
        ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            && ProcessInfo.processInfo.environment["TERM"] != "dumb"
            && isatty(fileno(stdout)) == 1
    }

    private static func style(_ string: String, _ codes: String) -> String {
        colorEnabled ? "\u{1B}[\(codes)m\(string)\u{1B}[0m" : string
    }

    public static func bold(_ string: String) -> String { style(string, "1") }
    public static func dim(_ string: String) -> String { style(string, "2") }
    public static func red(_ string: String) -> String { style(string, "31") }
    public static func green(_ string: String) -> String { style(string, "32") }
    public static func yellow(_ string: String) -> String { style(string, "33") }
    public static func cyan(_ string: String) -> String { style(string, "36") }

    public static func err(_ string: String) {
        FileHandle.standardError.write(Data((string + "\n").utf8))
    }

    public static func confirm(_ prompt: String, default defaultValue: Bool = false) -> Bool {
        guard isatty(fileno(stdin)) == 1 else { return defaultValue }
        let hint = defaultValue ? "[Y/n]" : "[y/N]"
        print("\(sanitize(prompt)) \(hint) ", terminator: "")
        guard let line = readLine() else { return defaultValue }
        let answer = line.trimmingCharacters(in: .whitespaces).lowercased()
        if answer.isEmpty { return defaultValue }
        return answer == "y" || answer == "yes"
    }

    public static func bar(fraction: Double, width: Int = 24) -> String {
        let filled = filledCount(fraction: fraction, width: width)
        return String(repeating: "█", count: filled)
            + String(repeating: "░", count: max(0, width) - filled)
    }

    static func filledCount(fraction: Double, width: Int) -> Int {
        let clamped = max(0, min(1, fraction))
        return Int((Double(max(0, width)) * clamped).rounded())
    }

    public static func sanitize(_ string: String) -> String {
        var output = ""
        output.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x20...0x7E, 0xA0...0x10FFFF:
                if scalar.value >= 0x7F && scalar.value <= 0x9F {
                    output.append("�")
                } else {
                    output.unicodeScalars.append(scalar)
                }
            case 0x09:
                output.append(" ")
            default:
                output.append("�")
            }
        }
        return output
    }

    public static func displayWidth(_ spans: [Span]) -> Int {
        spans.reduce(0) { $0 + displayWidth(sanitize($1.text)) }
    }

    public static func displayWidth(_ string: String) -> Int {
        _ = localeConfigured
        var width = 0
        var escapeState = 0
        for scalar in string.unicodeScalars {
            if escapeState == 1 {
                escapeState = scalar.value == 0x5B ? 2 : 0
                continue
            }
            if escapeState == 2 {
                if scalar.value >= 0x40 && scalar.value <= 0x7E {
                    escapeState = 0
                }
                continue
            }
            if scalar.value == 0x1B {
                escapeState = 1
                continue
            }
            let scalarWidth = wcwidth(wchar_t(scalar.value))
            width += scalarWidth > 0 ? Int(scalarWidth) : 0
        }
        return width
    }

    public static func pad(_ string: String, to width: Int) -> String {
        let missing = max(0, width - displayWidth(string))
        return string + String(repeating: " ", count: missing)
    }

    public static func truncate(_ string: String, to width: Int, middle: Bool = false) -> String {
        let safe = sanitize(string)
        guard width > 0 else { return "" }
        guard displayWidth(safe) > width else { return safe }
        guard width > 1 else { return "…" }

        if middle {
            let leftWidth = (width - 1) / 2
            let rightWidth = width - 1 - leftWidth
            return prefix(safe, width: leftWidth) + "…" + suffix(safe, width: rightWidth)
        }
        return prefix(safe, width: width - 1) + "…"
    }

    private static func prefix(_ string: String, width: Int) -> String {
        var output = ""
        var used = 0
        for character in string {
            let value = String(character)
            let characterWidth = displayWidth(value)
            guard used + characterWidth <= width else { break }
            output.append(character)
            used += characterWidth
        }
        return output
    }

    private static func suffix(_ string: String, width: Int) -> String {
        var characters: [Character] = []
        var used = 0
        for character in string.reversed() {
            let value = String(character)
            let characterWidth = displayWidth(value)
            guard used + characterWidth <= width else { break }
            characters.append(character)
            used += characterWidth
        }
        return String(characters.reversed())
    }
}

extension Term {
    public static func wrap(_ string: String, width: Int) -> [String] {
        let safe = sanitize(string)
        guard !safe.isEmpty else { return [""] }
        var lines: [String] = []
        var current = ""
        var used = 0
        for character in safe {
            let characterWidth = max(0, displayWidth(String(character)))
            if used + characterWidth > width && !current.isEmpty {
                lines.append(current)
                current = ""
                used = 0
            }
            current.append(character)
            used += characterWidth
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [""] : lines
    }

    public static func wordWrap(_ string: String, width: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        var gap = ""
        for token in wordTokens(sanitize(string)) {
            guard !token.isSpaces else {
                gap = token.text
                continue
            }
            let word = token.text
            if displayWidth(word) <= width {
                if current.isEmpty {
                    current = word
                } else if displayWidth(current) + displayWidth(gap) + displayWidth(word) <= width {
                    current += gap + word
                } else {
                    lines.append(current)
                    current = word
                }
                continue
            }
            if !current.isEmpty { lines.append(current) }
            let pieces = wrap(word, width: width)
            lines += pieces.dropLast()
            current = pieces[pieces.count - 1]
        }
        lines.append(current)
        return lines
    }

    private static func wordTokens(_ string: String) -> [(text: String, isSpaces: Bool)] {
        var tokens: [(text: String, isSpaces: Bool)] = []
        for character in string {
            let isSpace = character == " "
            if let last = tokens.last, last.isSpaces == isSpace {
                tokens[tokens.count - 1].text.append(character)
            } else {
                tokens.append((String(character), isSpace))
            }
        }
        return tokens
    }
}

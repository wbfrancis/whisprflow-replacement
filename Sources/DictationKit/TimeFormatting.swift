/// Rewrites spoken clock times in a transcript to `H:MM` notation — "three o'clock" → 3:00,
/// "three twenty" → 3:20, "quarter past four" → 4:15, "ten to six" → 5:50. Times only: bare
/// numbers ("404", "four hundred", "three dollars") are left untouched.
///
/// Everything outside a matched time — whitespace runs, newlines, surrounding punctuation —
/// is preserved exactly; only the matched span is replaced. Because "hour + minutes" is a
/// real spoken time, a few phrases are inherently ambiguous and will convert: "three twenty
/// dollars" → "3:20 dollars", "nine eleven" → "9:11". That's the cost of honoring
/// "three twenty" → 3:20; it's rare in dictation and accepted here.
///
/// A pure text transform, run on the transcript before it's pasted, and covered by the eval
/// harness (the Levels fixtures expect "3:00").
public enum TimeFormatting {
    public static func format(_ text: String) -> String {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return text }
        let clean = tokens.map { cleaned($0.raw) }

        // Rebuild by copying the original text verbatim between matches and replacing only
        // the matched spans — so whitespace and punctuation outside a time are untouched.
        var result = ""
        var cursor = text.startIndex
        var i = 0
        while i < tokens.count {
            guard let match = matchTime(clean, at: i) else { i += 1; continue }
            let first = tokens[i], last = tokens[i + match.length - 1]
            result += text[cursor..<first.start]
            result += leadingPunctuation(first.raw) + match.formatted + trailingPunctuation(last.raw)
            cursor = last.end
            i += match.length
        }
        result += text[cursor...]
        return result
    }

    // MARK: - Tokens

    private struct Token { let raw: String; let start: String.Index; let end: String.Index }

    /// Split into maximal non-whitespace runs, each with its range in the original string.
    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var i = text.startIndex
        while i < text.endIndex {
            while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
            guard i < text.endIndex else { break }
            let start = i
            while i < text.endIndex, !text[i].isWhitespace { i = text.index(after: i) }
            tokens.append(Token(raw: String(text[start..<i]), start: start, end: i))
        }
        return tokens
    }

    // MARK: - Matching

    private struct Match { let formatted: String; let length: Int }

    /// Try each time shape at position `i`, most specific first.
    private static func matchTime(_ t: [String], at i: Int) -> Match? {
        // "quarter/half past|to <hour>"
        if i + 2 < t.count, let base = quarterHalf(t[i]),
           let dir = direction(t[i + 1]), let hour = hourValue(t[i + 2]) {
            return Match(formatted: clock(hour: hour, minute: base, direction: dir), length: 3)
        }
        // "<minutes> past|to <hour>"  (e.g. "ten past three", "twenty five to four")
        if let m = minutes(t, at: i), i + m.length + 1 < t.count,
           let dir = direction(t[i + m.length]), let hour = hourValue(t[i + m.length + 1]) {
            return Match(formatted: clock(hour: hour, minute: m.value, direction: dir),
                         length: m.length + 2)
        }
        // "<hour> o'clock"
        if i + 1 < t.count, let hour = hourValue(t[i]), isOClock(t[i + 1]) {
            return Match(formatted: "\(hour):00", length: 2)
        }
        // "<hour> <minutes>" bare — only for time-shaped minutes (≥10, or a leading "oh N"),
        // so "three four" isn't misread as 3:04 while "three twenty" / "three oh five" are.
        if let hour = hourValue(t[i]), let m = minutes(t, at: i + 1), m.timeShaped {
            return Match(formatted: "\(hour):\(pad(m.value))", length: 1 + m.length)
        }
        return nil
    }

    /// Compose an `H:MM` for a "past"/"to" phrase. "to" counts back from the named hour.
    private static func clock(hour: Int, minute: Int, direction dir: Direction) -> String {
        switch dir {
        case .past: return "\(hour):\(pad(minute))"
        case .to:
            let h = hour - 1 <= 0 ? 12 : hour - 1
            return "\(h):\(pad(60 - minute))"
        }
    }

    private enum Direction { case past, to }
    private static func direction(_ s: String) -> Direction? {
        s == "past" ? .past : (s == "to" ? .to : nil)
    }

    private static func quarterHalf(_ s: String) -> Int? {
        s == "quarter" ? 15 : (s == "half" ? 30 : nil)
    }

    private static func isOClock(_ s: String) -> Bool { s == "o'clock" || s == "oclock" }

    // MARK: - Numbers

    private static let ones: [String: Int] = [
        "zero": 0, "oh": 0, "o": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]
    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50]

    /// An hour 1–12, from a digit or a word.
    private static func hourValue(_ s: String) -> Int? {
        if let n = Int(s), (1...12).contains(n) { return n }
        if let n = ones[s], (1...9).contains(n) { return n }
        if let n = teens[s], (10...12).contains(n) { return n }
        return nil
    }

    private struct Minutes { let value: Int; let length: Int; let timeShaped: Bool }

    /// Parse a 0–59 minute value starting at `i`. `timeShaped` marks forms that read as a
    /// clock minute (≥10, or a leading zero like "oh five") — used to gate the bare pattern.
    private static func minutes(_ t: [String], at i: Int) -> Minutes? {
        guard i < t.count else { return nil }
        let token = t[i]

        // "twenty-five" as one token.
        if token.contains("-") {
            let parts = token.split(separator: "-").map(String.init)
            if parts.count == 2, let tenv = tens[parts[0]], let onev = ones[parts[1]], (1...9).contains(onev) {
                return Minutes(value: tenv + onev, length: 1, timeShaped: true)
            }
        }
        if let n = Int(token), (0...59).contains(n) {
            return Minutes(value: n, length: 1, timeShaped: n >= 10 || token.hasPrefix("0"))
        }
        if let tenv = tens[token] {
            if i + 1 < t.count, let onev = ones[t[i + 1]], (1...9).contains(onev) {
                return Minutes(value: tenv + onev, length: 2, timeShaped: true)  // "twenty five"
            }
            return Minutes(value: tenv, length: 1, timeShaped: true)
        }
        if let teenv = teens[token] {
            return Minutes(value: teenv, length: 1, timeShaped: true)
        }
        // "oh five" / "o five" / "zero five" → leading-zero minute.
        if ["oh", "o", "zero"].contains(token), i + 1 < t.count,
           let onev = ones[t[i + 1]], (1...9).contains(onev) {
            return Minutes(value: onev, length: 2, timeShaped: true)
        }
        if let onev = ones[token], (1...9).contains(onev) {
            return Minutes(value: onev, length: 1, timeShaped: false)  // bare single digit
        }
        return nil
    }

    // MARK: - Token helpers

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// Lowercased, with leading/trailing punctuation stripped (keeps the apostrophe in
    /// "o'clock" and internal hyphens). A curly apostrophe is normalized to straight so
    /// "o’clock" still matches.
    private static func cleaned(_ s: String) -> String {
        var t = Substring(s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'"))
        while let f = t.first, !(f.isLetter || f.isNumber) { t = t.dropFirst() }
        while let l = t.last, !(l.isLetter || l.isNumber) { t = t.dropLast() }
        return String(t)
    }

    private static func leadingPunctuation(_ s: String) -> String {
        var prefix = ""
        for ch in s {
            if ch.isLetter || ch.isNumber { break }
            prefix += String(ch)
        }
        return prefix
    }

    private static func trailingPunctuation(_ s: String) -> String {
        var suffix = ""
        for ch in s.reversed() {
            if ch.isLetter || ch.isNumber { break }
            suffix = String(ch) + suffix
        }
        return suffix
    }
}

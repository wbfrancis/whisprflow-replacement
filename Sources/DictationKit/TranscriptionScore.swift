/// Scoring for the transcription eval harness: how close a produced transcript is to the
/// expected one, normalized so casing and punctuation don't count against a match.
public enum TranscriptionScore {
    /// Lowercase, drop punctuation (keeping intra-word apostrophes), split into words.
    public static func normalize(_ text: String) -> [String] {
        let mapped = text.lowercased().map { ch -> Character in
            (ch.isLetter || ch.isNumber || ch == "'") ? ch : " "
        }
        return String(mapped).split(separator: " ").map(String.init)
    }

    /// Word error rate: word-level edit distance between expected and got, over the expected
    /// word count. 0 is perfect; >1 is possible when there are many spurious insertions
    /// (which is exactly what a hallucinated continuation looks like).
    public static func wer(expected: String, got: String) -> Double {
        let e = normalize(expected)
        let g = normalize(got)
        guard !e.isEmpty else { return g.isEmpty ? 0 : 1 }
        return Double(editDistance(e, g)) / Double(e.count)
    }

    /// Levenshtein distance over word tokens (one row, O(n·m) time, O(m) space).
    static func editDistance(_ a: [String], _ b: [String]) -> Int {
        let n = a.count, m = b.count
        if n == 0 { return m }
        if m == 0 { return n }
        var row = Array(0...m)
        for i in 1...n {
            var prevDiagonal = row[0]
            row[0] = i
            for j in 1...m {
                let above = row[j]
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                row[j] = min(row[j] + 1, row[j - 1] + 1, prevDiagonal + cost)
                prevDiagonal = above
            }
        }
        return row[m]
    }
}

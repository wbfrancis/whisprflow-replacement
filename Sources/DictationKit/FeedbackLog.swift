import Foundation

/// Appends free-form feedback notes to a Markdown file the user can jot into from the menu
/// bar, so a later round of improvements has one place to read. The file lives outside the
/// build tree (survives rebuilds and a `.app` deploy), and each note is timestamped so the
/// order and rough date of a request are recoverable. The entry formatting is a pure static
/// so it's testable without touching disk.
public struct FeedbackLog {
    /// The Markdown file notes are appended to. Defaults to
    /// `~/Library/Application Support/whisper/feedback.md`.
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = appSupport.appendingPathComponent("whisper/feedback.md", isDirectory: false)
        }
    }

    /// One Markdown list entry: an ISO-8601 timestamp in the local zone, then the note with
    /// its inner newlines folded to spaces so a multi-line jot stays one readable bullet.
    /// Returns `nil` for a note that's empty once trimmed, so blank submissions are dropped.
    public static func entry(_ note: String, at date: Date) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let oneLine = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        let stamp = formatter.string(from: date)
        return "- **\(stamp)** — \(oneLine)\n"
    }

    /// Append a note. No-op for a blank note. Creates the file (with a heading) on first use.
    /// Throws only on a real filesystem failure, which the caller surfaces to the menu.
    @discardableResult
    public func append(_ note: String, at date: Date = Date()) throws -> Bool {
        guard let entry = Self.entry(note, at: date) else { return false }
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(entry.utf8))
        } else {
            let header = "# whisper feedback\n\n"
            try Data((header + entry).utf8).write(to: fileURL)
        }
        return true
    }
}

// PROTOTYPE — throwaway. Answers Q2: does pasteboard paste + Cmd-V land text at
// the cursor in real apps, and does clipboard save-and-restore work?
// Usage: swift paste-test.swift "text to inject"
// Needs Accessibility permission for your terminal (System Settings > Privacy &
// Security > Accessibility). After launch you get 4 seconds to click into a
// target app (browser, Notes, Slack, a code editor) and place your cursor.
import AppKit
import CoreGraphics
import Foundation

let inject = CommandLine.arguments.count >= 2
    ? CommandLine.arguments[1]
    : "The quick brown fox jumps over the lazy dog. 12345."

let pb = NSPasteboard.general

// 1) Save whatever is currently on the clipboard (string only, for this test).
let saved = pb.string(forType: .string)
print("Saved existing clipboard: \(saved.map { "\"\($0)\"" } ?? "(none / non-text)")")

// 2) Put our text on the clipboard.
pb.clearContents()
pb.setString(inject, forType: .string)

print("Click into a target app and place your cursor. Pasting in 4 seconds...")
for i in (1...4).reversed() {
    print("  \(i)...")
    Thread.sleep(forTimeInterval: 1.0)
}

// 3) Synthesize Cmd-V (needs Accessibility permission).
guard let src = CGEventSource(stateID: .combinedSessionState) else {
    FileHandle.standardError.write("Could not create event source.\n".data(using: .utf8)!)
    exit(1)
}
let vKey: CGKeyCode = 9  // 'v'
let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
down?.flags = .maskCommand
let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
up?.flags = .maskCommand
down?.post(tap: .cghidEventTap)
up?.post(tap: .cghidEventTap)
print("Posted Cmd-V.")

// 4) Restore the previous clipboard after the paste has been consumed.
Thread.sleep(forTimeInterval: 0.4)
pb.clearContents()
if let saved = saved {
    pb.setString(saved, forType: .string)
    print("Restored previous clipboard.")
} else {
    print("No previous text clipboard to restore (left empty).")
}

print("""

Now check by hand:
  - Did \"\(inject)\" appear at your cursor in the target app?
  - Is your ORIGINAL clipboard back? (Cmd-V again somewhere to confirm.)
If nothing pasted, the terminal likely lacks Accessibility permission.
""")

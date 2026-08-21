// DictationKit — the OS-independent core of the dictation app.
//
// Ticket #2 populates this with the seam protocols (HotkeySource, AudioSource,
// TranscriptionEngine, TextInjector) and the DictationController state machine,
// all unit-tested with fakes. For now it holds only the package identity so the
// target compiles and the executable + test targets can depend on it.

public enum DictationKit {
    public static let version = "0.1.0"
}

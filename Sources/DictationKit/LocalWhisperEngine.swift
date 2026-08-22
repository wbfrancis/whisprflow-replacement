import Foundation
import CWhisper

/// Owns the whisper.cpp context so its C resource is freed in a plain (non-isolated)
/// deinit, away from the engine's `@MainActor` isolation.
private final class WhisperContext {
    let pointer: OpaquePointer
    init(pointer: OpaquePointer) { self.pointer = pointer }
    deinit { whisper_free(pointer) }
}

/// `TranscriptionEngine` backed by whisper.cpp, linked in-process (via the CWhisper
/// module) so the model is loaded once and kept resident across utterances.
///
/// Note: transcription is CPU/GPU-bound (~1s warm). Because the seam is `@MainActor`,
/// this runs on the main actor for v1, which is acceptable for a menu-bar agent that
/// has no other UI to service mid-dictation. Moving the whisper call off-main is a
/// later optimization (the whisper context isn't `Sendable`, so it needs a guarded box).
@MainActor
public final class LocalWhisperEngine: TranscriptionEngine {
    private var context: WhisperContext?
    private let modelPath: String

    public init(modelPath: String) {
        self.modelPath = modelPath
    }

    /// Ensure the model is present (downloading on first run) via the store, then build
    /// an engine pointed at it. This is the seam the app assembles at launch (#7).
    public static func resident(
        modelStore: WhisperModelStore = WhisperModelStore()
    ) async throws -> LocalWhisperEngine {
        let url = try await modelStore.ensureAvailable()
        return LocalWhisperEngine(modelPath: url.path)
    }

    /// Load the model and run one transcription on silence, paying the one-time Metal
    /// shader-compile cost at launch so the first real dictation isn't slow.
    public func warmUp() async {
        try? loadIfNeeded()
        _ = try? run(samples: [Float](repeating: 0, count: 16_000))  // 1s of silence
    }

    public func transcribe(_ audio: CapturedAudio) async throws -> String {
        // Cut trailing silence first — whisper hallucinates a continuation to fill it
        // (e.g. "1 2 3 4 5 6" → "…7 8 9 10").
        try await transcribeRaw(SilenceTrim.trimmingTrailingSilence(audio.samples))
    }

    /// Transcribe 16kHz mono samples with no silence trimming applied. The eval harness
    /// uses this so it can apply (and tune) the trim itself.
    public func transcribeRaw(_ samples: [Float]) async throws -> String {
        try loadIfNeeded()
        guard !samples.isEmpty else { return "" }  // nothing to transcribe → no-audio path
        return try run(samples: samples)
    }

    // MARK: - whisper.cpp

    /// ggml's compute backends (CPU/Metal) are separate plugins loaded at runtime. They
    /// aren't pulled in by linking `-lggml`, so load them once from ggml's plugin dir —
    /// without this, whisper aborts with "backends = 0".
    private static var backendsLoaded = false
    private func loadBackendsIfNeeded() throws {
        guard !Self.backendsLoaded else { return }
        let path = ProcessInfo.processInfo.environment["GGML_BACKEND_PATH"]
            ?? "/opt/homebrew/opt/ggml/libexec"
        ggml_backend_load_all_from_path(path)
        // Verify a backend actually registered; otherwise whisper.cpp would abort the
        // process (uncatchable) on init. Throw a catchable error instead, and don't
        // cache a failed load.
        guard ggml_backend_reg_count() > 0 else {
            throw WhisperError.backendsUnavailable(path)
        }
        Self.backendsLoaded = true
    }

    private func loadIfNeeded() throws {
        guard context == nil else { return }
        try loadBackendsIfNeeded()
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        guard let pointer = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw WhisperError.modelLoadFailed(modelPath)
        }
        context = WhisperContext(pointer: pointer)
    }

    private func run(samples: [Float]) throws -> String {
        guard let ctx = context?.pointer else { throw WhisperError.notLoaded }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.no_timestamps = true
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))

        // Anti-hallucination: a push-to-talk clip is one short utterance, so force a single
        // segment and don't carry context between calls; suppress non-speech tokens; and
        // keep decoding deterministic (no temperature fallback that can wander into a
        // plausible-but-wrong continuation).
        params.single_segment = true
        params.no_context = true
        params.suppress_blank = true
        params.suppress_nst = true
        params.temperature = 0.0
        params.temperature_inc = 0.0

        let status: Int32 = "en".withCString { lang in
            params.language = lang
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
        }
        guard status == 0 else { throw WhisperError.transcriptionFailed(status) }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let segment = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segment)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

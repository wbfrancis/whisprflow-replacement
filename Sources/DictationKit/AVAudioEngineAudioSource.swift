import AVFoundation

public enum AudioCaptureError: Error, Equatable {
    /// The mic's hardware format can't be converted to the 16kHz mono the engine needs.
    case unsupportedFormat
}

/// A tiny thread-safe boolean the realtime tap reads to know when to collect samples.
/// Lock-guarded and `@unchecked Sendable` so it can cross into the tap closure.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return on
    }

    func set(_ newValue: Bool) {
        lock.lock(); on = newValue; lock.unlock()
    }
}

/// Thread-safe accumulator for captured samples. The mic tap fires on a realtime audio
/// thread, so appends are lock-guarded and the class is `@unchecked Sendable` to cross
/// into the tap closure.
final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ new: [Float]) {
        lock.lock()
        samples.append(contentsOf: new)
        lock.unlock()
    }

    /// Return everything captured so far and reset for the next utterance.
    func drain() -> [Float] {
        lock.lock()
        defer { samples.removeAll(); lock.unlock() }
        return samples
    }
}

/// Resamples mic buffers (any hardware rate, mono or stereo) to 16kHz mono float via one
/// persistent `AVAudioConverter`. Pulled out of the engine so the conversion — the part
/// that must be right (rate, channel downmix, duration) — is unit-tested with synthetic
/// buffers, no microphone. `@unchecked Sendable`: the converter is touched only from the
/// single audio thread once installed (or one test thread), never concurrently.
final class AudioResampler: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let source: AVAudioFormat
    private let target: AVAudioFormat

    init?(from source: AVAudioFormat, to target: AVAudioFormat = AVAudioEngineAudioSource.whisperFormat) {
        guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
        self.converter = converter
        self.source = source
        self.target = target
    }

    /// Convert one input buffer to 16kHz mono samples. Returns `[]` if nothing converted.
    func resample(_ input: AVAudioPCMBuffer) -> [Float] {
        let ratio = target.sampleRate / source.sampleRate
        // Output capacity = input frames scaled by the rate ratio, plus headroom for the
        // resampling filter's edge frames, which can push the count slightly past the ratio.
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error, conversionError == nil,
              output.frameLength > 0, let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

/// `AudioSource` over `AVAudioEngine`. Taps the mic, resamples to 16kHz mono, and hands
/// the samples over on stop. Samples are accumulated in memory as `[Float]`, so there's no
/// WAV header to finalize — the prototype's zero-length-file bug can't recur; an empty
/// capture is simply an empty sample array, which drives the controller's "no audio" path.
///
/// The engine is started once and kept running (see `prewarm`), and each utterance just
/// toggles collection on and off. Starting the engine cold on every key-down added enough
/// latency to clip the first word, so the mic is held hot instead. The cost is that the
/// mic stays active — and macOS shows its in-use indicator — for the whole session.
@MainActor
public final class AVAudioEngineAudioSource: AudioSource {
    /// 16kHz mono float — the format whisper.cpp consumes; captured audio is resampled to
    /// it. `nonisolated(unsafe)`: `AVAudioFormat` isn't `Sendable`, but an instance is
    /// immutable once built, so sharing this one read-only value across threads is safe.
    nonisolated(unsafe) public static let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    private let engine = AVAudioEngine()
    private let buffer = SampleBuffer()
    private let collecting = Flag()
    private var running = false

    public init() {}

    /// Start the mic engine ahead of first use so the first key-down has no cold-start
    /// latency. Safe to call at launch; the first real capture reuses the hot engine.
    public func prewarm() throws {
        try ensureRunning()
    }

    public func startCapture() throws {
        try ensureRunning()   // no-op once hot; retries if a prior prewarm was blocked
        _ = buffer.drain()    // discard anything left from a prior capture
        collecting.set(true)
    }

    public func stopCapture() async -> CapturedAudio {
        guard running else { return CapturedAudio(samples: []) }
        collecting.set(false)
        return CapturedAudio(samples: buffer.drain())
    }

    /// Install the tap and start the engine once; keep both hot for the session. Idempotent.
    private func ensureRunning() throws {
        guard !running else { return }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let resampler = AudioResampler(from: inputFormat) else {
            throw AudioCaptureError.unsupportedFormat
        }

        // The tap fires on the realtime audio thread, so the block is `@Sendable` (never
        // main-actor isolated) and captures only Sendable values — the collection gate, the
        // resampler, and the sample sink — never `self`.
        let sink = buffer
        let gate = collecting
        let block: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { pcm, _ in
            guard gate.value else { return }   // drop buffers outside an utterance
            let samples = resampler.resample(pcm)
            if !samples.isEmpty { sink.append(samples) }
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: block)

        engine.prepare()
        do {
            try engine.start()  // throws if the mic can't be opened (e.g. no permission)
        } catch {
            // Start failed, so remove the tap we just installed; otherwise a retry would
            // hit AVAudioEngine's one-tap-per-bus limit and trap.
            input.removeTap(onBus: 0)
            throw error
        }
        running = true
    }
}

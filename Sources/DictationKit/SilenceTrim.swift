/// Trims trailing near-silence from a 16kHz mono clip before it reaches whisper.
///
/// Whisper is generative: given a tail of silence after speech, its decoder keeps emitting
/// the text it expects to come next — the classic "counting keeps counting" hallucination.
/// Cutting the trailing silence removes the canvas it fills. Leading audio is left alone so
/// the first word is never clipped.
///
/// The silence threshold is **adaptive** — relative to the clip's own peak — so a quiet or
/// whispered utterance isn't mistaken for silence and discarded, while a loud clip still
/// gets its trailing quiet trimmed. An absolute floor keeps pure noise from counting as
/// speech.
public enum SilenceTrim {
    /// - Parameters:
    ///   - absoluteFloor: RMS below this (on the -1…1 scale) is silence regardless of peak;
    ///     stops a near-silent clip of noise from being treated as speech.
    ///   - relativeFraction: a window counts as speech if its RMS is at least this fraction
    ///     of the clip's loudest window — the lever that keeps whispers intact.
    ///   - window: samples per RMS window (320 = 20ms at 16kHz).
    ///   - pad: samples of audio kept after the last speech, so the final word's tail isn't
    ///     clipped (4800 = 300ms at 16kHz).
    public static func trimmingTrailingSilence(
        _ samples: [Float],
        absoluteFloor: Float = 0.0025,
        relativeFraction: Float = 0.12,
        window: Int = 320,
        pad: Int = 4800
    ) -> [Float] {
        guard !samples.isEmpty else { return samples }

        // One RMS per window, plus the loudest of them.
        var windowRMS: [(end: Int, rms: Float)] = []
        var peak: Float = 0
        var start = 0
        while start < samples.count {
            let end = min(start + window, samples.count)
            var sumSquares: Float = 0
            for i in start..<end { sumSquares += samples[i] * samples[i] }
            let rms = (sumSquares / Float(end - start)).squareRoot()
            windowRMS.append((end, rms))
            peak = max(peak, rms)
            start = end
        }

        let threshold = max(absoluteFloor, relativeFraction * peak)
        let lastLoudEnd = windowRMS.last { $0.rms >= threshold }?.end ?? -1
        guard lastLoudEnd >= 0 else { return [] }  // all silence → empty (the no-audio path)

        let cut = min(samples.count, lastLoudEnd + pad)
        return Array(samples[0..<cut])
    }
}

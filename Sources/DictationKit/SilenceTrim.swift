/// Trims trailing near-silence from a 16kHz mono clip before it reaches whisper.
///
/// Whisper is generative: given a tail of silence after speech, its decoder keeps emitting
/// the text it expects to come next — the classic "counting keeps counting" hallucination.
/// Cutting the trailing silence removes the canvas it fills. Leading audio is left alone so
/// the first word is never clipped.
public enum SilenceTrim {
    /// - Parameters:
    ///   - threshold: RMS below this (on the -1…1 float scale) counts as silence.
    ///   - window: samples per RMS window (320 = 20ms at 16kHz).
    ///   - pad: samples of audio to keep after the last sound, so the tail of the final
    ///     word isn't clipped (3200 = 200ms at 16kHz).
    public static func trimmingTrailingSilence(
        _ samples: [Float],
        threshold: Float = 0.01,
        window: Int = 320,
        pad: Int = 3200
    ) -> [Float] {
        guard !samples.isEmpty else { return samples }

        // Walk the clip in windows; remember the end of the last one loud enough to be speech.
        var lastLoudEnd = -1
        var start = 0
        while start < samples.count {
            let end = min(start + window, samples.count)
            var sumSquares: Float = 0
            for i in start..<end { sumSquares += samples[i] * samples[i] }
            let rms = (sumSquares / Float(end - start)).squareRoot()
            if rms >= threshold { lastLoudEnd = end }
            start = end
        }

        guard lastLoudEnd >= 0 else { return [] }  // all silence → empty (the no-audio path)
        let cut = min(samples.count, lastLoudEnd + pad)
        return Array(samples[0..<cut])
    }
}

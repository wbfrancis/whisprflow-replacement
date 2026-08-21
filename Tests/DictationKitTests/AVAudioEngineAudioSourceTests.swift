import XCTest
import AVFoundation
@testable import DictationKit

/// Exercises the resampling/accumulation the audio source is built from, using synthetic
/// buffers so no microphone or permission is involved. The `AVAudioEngine` plumbing itself
/// is the untested real-OS boundary, like the whisper/paste/hotkey adapters.
final class AVAudioEngineAudioSourceTests: XCTestCase {

    private func format(_ sampleRate: Double, _ channels: AVAudioChannelCount) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                      channels: channels, interleaved: false)!
    }

    private func buffer(_ format: AVAudioFormat, frames: AVAudioFrameCount,
                        fill: (Int) -> Float) -> AVAudioPCMBuffer {
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        for ch in 0..<Int(format.channelCount) {
            let ptr = buf.floatChannelData![ch]
            for i in 0..<Int(frames) { ptr[i] = fill(i) }
        }
        return buf
    }

    // MARK: - Target format

    func testWhisperFormatIs16kMono() {
        XCTAssertEqual(AVAudioEngineAudioSource.whisperFormat.sampleRate, 16_000)
        XCTAssertEqual(AVAudioEngineAudioSource.whisperFormat.channelCount, 1)
    }

    // MARK: - Resampling (AC2: 16k mono; AC3: correct non-zero duration)

    func testDownsamples48kStereoToRoughly16kMono() {
        let resampler = AudioResampler(from: format(48_000, 2))!
        // 1 second of 48kHz stereo audio.
        let out = resampler.resample(buffer(format(48_000, 2), frames: 48_000) { _ in 0.3 })

        // ~16000 samples out (allow for the converter's edge handling).
        XCTAssertGreaterThan(out.count, 14_000)
        XCTAssertLessThan(out.count, 17_000)
        let duration = Double(out.count) / AVAudioEngineAudioSource.whisperFormat.sampleRate
        XCTAssertEqual(duration, 1.0, accuracy: 0.1, "1s in should yield ~1s of 16kHz samples")
    }

    func testPassesThrough16kMonoUnchanged() {
        let resampler = AudioResampler(from: format(16_000, 1))!
        let out = resampler.resample(buffer(format(16_000, 1), frames: 16_000) { _ in 0.2 })
        XCTAssertEqual(Double(out.count) / AVAudioEngineAudioSource.whisperFormat.sampleRate, 1.0, accuracy: 0.05)
    }

    func testSignalSurvivesDownsampling() {
        let resampler = AudioResampler(from: format(48_000, 1))!
        // A 440Hz tone — well under the 8kHz Nyquist limit of 16kHz, so it must survive.
        let out = resampler.resample(buffer(format(48_000, 1), frames: 48_000) { i in
            0.5 * sinf(2 * .pi * 440 * Float(i) / 48_000)
        })
        let peak = out.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.1, "the tone should be present in the resampled audio")
    }

    // MARK: - Silent vs empty (AC4: a silent/empty capture is distinguishable)

    func testSilenceProducesFramesNotAnEmptyCapture() {
        let resampler = AudioResampler(from: format(48_000, 1))!
        let out = resampler.resample(buffer(format(48_000, 1), frames: 48_000) { _ in 0.0 })

        // Silence still yields frames (near-zero), so it is NOT an empty capture — that
        // distinction is what lets the controller tell "said nothing" from "no audio".
        XCTAssertFalse(CapturedAudio(samples: out).isEmpty)
        XCTAssertTrue(out.allSatisfy { abs($0) < 0.001 })
        XCTAssertTrue(CapturedAudio(samples: []).isEmpty, "no frames captured is the empty case")
    }

    // MARK: - Accumulation

    func testSampleBufferAccumulatesThenDrainsAndResets() {
        let buffer = SampleBuffer()
        buffer.append([1, 2])
        buffer.append([3])
        XCTAssertEqual(buffer.drain(), [1, 2, 3])
        XCTAssertEqual(buffer.drain(), [], "drain must reset for the next utterance")
    }
}

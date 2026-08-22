import AVFoundation

/// Decodes an audio file to the 16kHz mono float samples the engine consumes — the file
/// counterpart to the live mic path, used by the eval harness to feed fixtures through the
/// exact same resampling the microphone uses.
public enum AudioDecoding {
    public static func samples16kMono(fromFile url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioCaptureError.unsupportedFormat
        }
        try file.read(into: buffer)
        guard let resampler = AudioResampler(from: format) else {
            throw AudioCaptureError.unsupportedFormat
        }
        return resampler.resample(buffer)
    }
}

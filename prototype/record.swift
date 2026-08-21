// PROTOTYPE — throwaway. Records the mic via AVAudioEngine (same stack the real
// app will use) and writes a WAV. Starts on launch, stops when you press Return.
// Usage: swift record.swift /path/to/out.wav
import AVFoundation
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift record.swift <out.wav>\n".data(using: .utf8)!)
    exit(2)
}
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])

// Request mic permission (prompts for the host terminal on first run).
let sem = DispatchSemaphore(value: 0)
var granted = false
AVCaptureDevice.requestAccess(for: .audio) { ok in granted = ok; sem.signal() }
sem.wait()
guard granted else {
    FileHandle.standardError.write("Microphone access denied. Grant it to your terminal in System Settings > Privacy & Security > Microphone.\n".data(using: .utf8)!)
    exit(3)
}

let engine = AVAudioEngine()
let input = engine.inputNode
let inFormat = input.outputFormat(forBus: 0)

// Write in the mic's NATIVE format so every buffer write is guaranteed valid
// (no float/int mismatch). afconvert downsamples to 16k mono int16 afterward.
var file: AVAudioFile?
do {
    file = try AVAudioFile(forWriting: outURL, settings: inFormat.settings)
} catch {
    FileHandle.standardError.write("Failed to open output file: \(error)\n".data(using: .utf8)!)
    exit(4)
}

var frames: Int64 = 0
input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { buffer, _ in
    do {
        try file?.write(from: buffer)
        frames += Int64(buffer.frameLength)
    } catch {
        FileHandle.standardError.write("write error: \(error)\n".data(using: .utf8)!)
    }
}

do {
    try engine.start()
} catch {
    FileHandle.standardError.write("Failed to start audio engine: \(error)\n".data(using: .utf8)!)
    exit(5)
}

FileHandle.standardError.write("● Recording — speak now, then press Return to stop.\n".data(using: .utf8)!)
_ = readLine()  // blocks until Return

engine.stop()
input.removeTap(onBus: 0)
Thread.sleep(forTimeInterval: 0.1)  // let the last tap buffer flush
file = nil  // release -> AVAudioFile finalizes the WAV header (frame count)

let secs = inFormat.sampleRate > 0 ? Double(frames) / inFormat.sampleRate : 0
FileHandle.standardError.write(String(format: "■ Stopped. Captured %.2fs of audio.\n", secs).data(using: .utf8)!)
if frames == 0 {
    FileHandle.standardError.write("WARNING: no audio captured — check mic permission for your terminal.\n".data(using: .utf8)!)
}

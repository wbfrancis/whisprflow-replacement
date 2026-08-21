// swift-tools-version: 6.0
import PackageDescription

// Homebrew whisper.cpp install paths (from `brew --prefix`). pkg-config isn't
// installed on this machine, so the include/link flags are taken from whisper.pc
// and passed directly. Ties the build to the Homebrew install (fine — personal tool).
let whisperInclude = "-I/opt/homebrew/include"
let whisperLibDir = "-L/opt/homebrew/lib"

let package = Package(
    name: "whisprflow",
    platforms: [.macOS("14.6")],
    targets: [
        // C shim exposing the whisper.cpp C API to Swift, linked in-process so the
        // model stays resident across utterances.
        .target(
            name: "CWhisper",
            cSettings: [.unsafeFlags([whisperInclude])],
            linkerSettings: [
                .unsafeFlags([whisperLibDir, "-lwhisper", "-lggml", "-lggml-base"])
            ]
        ),
        // The testable core: dictation loop + seam protocols + local whisper engine.
        .target(
            name: "DictationKit",
            dependencies: ["CWhisper"],
            cSettings: [.unsafeFlags([whisperInclude])],
            swiftSettings: [.unsafeFlags(["-Xcc", whisperInclude])]
        ),
        .executableTarget(
            name: "whisprflow",
            dependencies: ["DictationKit"]
        ),
        .testTarget(
            name: "DictationKitTests",
            dependencies: ["DictationKit"]
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "whisprflow",
    platforms: [.macOS("14.6")],
    targets: [
        // The testable core: dictation loop + seam protocols (populated in #2).
        .target(name: "DictationKit"),
        // The menu-bar agent executable.
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

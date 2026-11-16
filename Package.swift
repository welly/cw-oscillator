// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Oscillator",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "OscillatorCore", targets: ["OscillatorCore"]),
        .library(name: "OscillatorAudio", targets: ["OscillatorAudio"]),
        .executable(name: "OscillatorApp", targets: ["OscillatorApp"]),
    ],
    targets: [
        // Platform-independent keyer, timing, Morse table, decoder and tone generator.
        // Foundation only, so the iOS app can share it.
        .target(name: "OscillatorCore"),
        // Low-latency sidetone output (AVAudioEngine), shared by the macOS and future iOS apps.
        .target(name: "OscillatorAudio", dependencies: ["OscillatorCore"]),
        // The macOS app: paddle input and the SwiftUI window.
        .executableTarget(name: "OscillatorApp", dependencies: ["OscillatorCore", "OscillatorAudio"]),
        .testTarget(name: "OscillatorCoreTests", dependencies: ["OscillatorCore"]),
    ],
    swiftLanguageModes: [.v5]
)

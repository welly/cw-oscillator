// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Oscillator",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "OscillatorCore", targets: ["OscillatorCore"]),
        .library(name: "OscillatorAudio", targets: ["OscillatorAudio"]),
        .library(name: "OscillatorUI", targets: ["OscillatorUI"]),
        .executable(name: "OscillatorApp", targets: ["OscillatorApp"]),
    ],
    targets: [
        // Platform-independent keyer, timing, Morse table, decoder and tone generator.
        // Foundation only, so the iOS app can share it.
        .target(name: "OscillatorCore"),
        // Low-latency sidetone output (AVAudioEngine), shared by the macOS and iOS apps.
        .target(name: "OscillatorAudio", dependencies: ["OscillatorCore"]),
        // The model, paddle input and SwiftUI screens for both apps. Shared views are in the
        // top folder; `Mac/` and `iOS/` hold each platform's own (guarded with `#if os`).
        .target(name: "OscillatorUI", dependencies: ["OscillatorCore", "OscillatorAudio"]),
        // The macOS app: a thin shell of scenes and menus around OscillatorUI.
        // The iOS app is the Xcode project in iOS/, which uses OscillatorUI the same way.
        .executableTarget(name: "OscillatorApp", dependencies: ["OscillatorUI"]),
        .testTarget(name: "OscillatorCoreTests", dependencies: ["OscillatorCore"]),
    ],
    swiftLanguageModes: [.v5]
)

# CW Training Oscillator

Practice oscillator and sending trainer for a paddle on a VBand USB adapter (Left Control = dit, Right Control = dah), for the Mac and (in progress) iPhone/iPad. See README.md for features.

- `OscillatorCore` is Foundation-only and must stay that way; `OscillatorAudio` is the AVAudioEngine sidetone. Both apps share them.
- `OscillatorUI` holds the model (`OscillatorModel`) and all the SwiftUI screens. Shared views sit in its top folder; `Mac/` (`ContentView`, NSEvent `PaddleInput`) and `iOS/` (`RootView`, GameController `PaddleInput`, touch pads) are each wrapped in `#if os(...)`. File names must differ between the two folders (SwiftPM rejects two `PaddleInput.swift`).
- `Sources/OscillatorApp` is only the Mac scenes and menus. The iOS app is `iOS/OscillatoriOS.xcodeproj` (target `OscillatoriOS`, iOS 17+, iPhone portrait, iPad any), which depends on this package and syncs `iOS/App/` automatically. Bundle ID `radio.g3ajm.Oscillator` on both; home-screen name "CW Oscillator".
- Run on iOS: `./scripts/run-ios-sim.sh ["iPhone 17"]`. On a real device, open the Xcode project, pick your team under Signing & Capabilities, and run.
- `swift scripts/make-icon.swift` writes the Mac `.icns` and the iOS 1024 px `AppIcon.png`.
- The keyer runs per sample inside the AVAudioSourceNode render block (`OscillatorEngine`). The render block takes the `OSAllocatedUnfairLock` once to read inputs and once to write marks/status per buffer; keep work there allocation-light and never block.
- Timing tests use a 1 kHz sample rate at 12 WPM so one unit is exactly 100 samples.
- Tests: `./scripts/test.sh`. App: `./scripts/build-app.sh [--install]`.

# CW Training Oscillator

Mac practice oscillator for a paddle on a VBand USB adapter (Left Control = dit, Right Control = dah). See README.md for features.

- `OscillatorCore` is Foundation-only and must stay that way: the iOS app (planned) will share it, and `OscillatorAudio`.
- The keyer runs per sample inside the AVAudioSourceNode render block (`OscillatorEngine`). The render block takes the `OSAllocatedUnfairLock` once to read inputs and once to write marks/status per buffer; keep work there allocation-light and never block.
- Timing tests use a 1 kHz sample rate at 12 WPM so one unit is exactly 100 samples.
- Tests: `./scripts/test.sh`. App: `./scripts/build-app.sh [--install]`.

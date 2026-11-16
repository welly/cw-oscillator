# CW Oscillator

A practice oscillator for the Mac: plug a Morse paddle in through a [VBand](https://hamradio.solutions/vband/) USB adapter and hear your CW, with an iambic keyer and a live copy of what you send.

## Features

- **Sidetone**: pitch 300–1200 Hz and volume, keyed with a 5 ms raised-cosine envelope (no clicks).
- **Speed**: 5–60 WPM (PARIS timing).
- **Keyer**: Iambic A, Iambic B or straight key; reverse paddles; dit/dah memory.
- **Autospace**: after a pause, the next character is held back until a full letter gap has passed, so your spacing comes out right.
- **Copy**: what you send is decoded as you go, prosigns shown as A̅R̅, S̅K̅, B̅T̅, K̅N̅, A̅S̅.
- **Last gap**: the silence between your last two characters, in units (a letter gap should be 3, a word gap 7). Over 4 is flagged as a long letter gap; 5 or more is copied as a word space.

## Paddle

The VBand adapter appears as a keyboard: the dit paddle is **Left Control** and the dah paddle is **Right Control**. Without a paddle, `[` and `]` do the same. The app only hears the paddle while its window is in front; if it loses focus mid-character the keyer lets go.

Wired headphones or the built-in speakers give the lowest delay (the app asks for a 128-frame buffer, under 3 ms). Bluetooth headphones add a noticeable lag that makes sending awkward.

## Building

Needs macOS 14 or later and Swift 6 (Xcode or the Command Line Tools).

```bash
./scripts/build-app.sh            # build/CW Oscillator.app
./scripts/build-app.sh --install  # and copy it to ~/Applications
./scripts/test.sh                 # keyer, timing and decoder tests
swift scripts/make-icon.swift     # regenerate Resources/AppIcon.icns
```

## Layout

- `Sources/OscillatorCore`: platform-independent timing, Morse table, keyer, decoder and tone generator (Foundation only).
- `Sources/OscillatorAudio`: the AVAudioEngine sidetone. The keyer runs inside the audio render callback, one step per sample, so element timing is exact. Ready for iOS as well.
- `Sources/OscillatorApp`: the macOS app: paddle input and the SwiftUI window.

## Licence

GNU GPL v3 or later. © 2026 Alastair Moore, G3AJM.

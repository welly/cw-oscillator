# CW Training Oscillator

A Morse sending trainer for the Mac: plug a paddle in through a [VBand](https://hamradio.solutions/vband/) USB adapter, hear your CW, and see how accurate your characters and spacing are.

## Features

- **Free or Practice**: a switch at the top of the window. Free is a plain practice oscillator: send anything, hear your sidetone and see it copied. Practice gives you targets and judges them.
- **Send this**: a target to send (your callsign, random callsigns, words or QSO phrases). Characters turn green or red as you send, and a bar under each gap shows the spacing: green right, orange a long letter gap, red an unwanted space inside a word or a missing one between words. Get it right and a new target appears; otherwise send it again. To start an attempt again part way through, send the error signal (eight dits; six or more, even if they break up into letters like S S I) or press Esc.
- **Timing strip**: your last few seconds of sending as bars, with each letter underneath and each gap's length in units. While you pause, the gap grows live with marks at 3 units (letter gap) and 7 (word gap).
- **Statistics** (⌘I): attempts, how many were right and your best run; the speed your sending works out at once your spacing is counted (your last five attempts at the current speed settings); average letter and word gaps with how consistent they are; long letter gaps, unwanted and missing spaces; and the characters you miss most. A chart shows your average letter gap for each attempt against the 3-unit target. For the session, with Reset.
- **Help**: the ? button or Help ▸ CW Training Oscillator Help explains units, letter gaps and word gaps.
- **Sidetone**: pitch 300–1200 Hz and volume, keyed with a 5 ms raised-cosine envelope (no clicks).
- **Speed**: character speed 5–60 WPM (PARIS timing).
- **Farnsworth spacing**: characters at full speed with the gaps between them stretched to a slower effective speed (ARRL formula). Your spacing is then judged against the stretched gaps, so a beginner isn't marked wrong for taking time between characters.
- **Keyer**: Iambic A, Iambic B or straight key; reverse paddles; dit/dah memory.
- **Autospace**: after a pause, the next character is held back until a full letter gap has passed, so your spacing comes out right.
- **Copy**: everything you send is decoded as you go, prosigns shown as A̅R̅, S̅K̅, B̅T̅, K̅N̅, A̅S̅, B̅K̅.

Sidetone, keyer and your callsign are in Settings (⌘,); speed is also in the main window.

## Spacing

Timing is in units, one unit being a dit. Characters are separated by 3 units and words by 7. Gaps between characters are measured in spacing units, which are dits without Farnsworth and the stretched unit with it, so 3 and 7 are always the targets. A gap of 2 dits ends a character; under 4 spacing units is a letter gap, 4 to 5 a long letter gap, and 5 or more a word space.

## Paddle

The VBand adapter appears as a keyboard: the dit paddle is **Left Control** and the dah paddle is **Right Control**. Without a paddle, `[` and `]` do the same. In Free mode, DIT and DAH lights by the timing strip show which paddle is pressed, handy for checking it's wired the right way round (Settings ▸ Reverse paddles swaps them). The app only hears the paddle while its window is in front; if it loses focus mid-character the keyer lets go.

Wired headphones or the built-in speakers give the lowest delay (the app asks for a 128-frame buffer, under 3 ms). Bluetooth headphones add a noticeable lag that makes sending awkward.

## Building

Needs macOS 14 or later and Swift 6 (Xcode or the Command Line Tools).

```bash
./scripts/build-app.sh            # build/CW Training Oscillator.app
./scripts/build-app.sh --install  # and copy it to ~/Applications
./scripts/test.sh                 # keyer, timing, decoder and scoring tests
swift scripts/make-icon.swift     # regenerate Resources/AppIcon.icns
```

## Layout

- `Sources/OscillatorCore`: platform-independent timing, Morse table, keyer, decoder, tone generator, practice targets and scoring (Foundation only).
- `Sources/OscillatorAudio`: the AVAudioEngine sidetone. The keyer runs inside the audio render callback, one step per sample, so element timing is exact. Ready for iOS as well.
- `Sources/OscillatorApp`: the macOS app: paddle input, the main window, timing strip, Settings and help.

## Licence

GNU GPL v3 or later. © 2026 Alastair Moore, G3AJM.

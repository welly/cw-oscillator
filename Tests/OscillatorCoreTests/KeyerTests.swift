import Foundation
import Testing
@testable import OscillatorCore

/// 1 kHz sample rate at 12 WPM: one unit is exactly 100 samples.
private let rate = 1000.0
private let twelve = MorseTiming(characterWPM: 12)

/// Runs the keyer over a paddle script of (dit, dah, samples) and returns the elements it sent.
private func run(_ mode: KeyerMode, timing: MorseTiming = twelve, autospace: Bool = false,
                 _ script: [(Bool, Bool, Int)], tail: Int = 1000) -> [Mark] {
    var keyer = Keyer(sampleRate: rate, settings: .init(mode: mode, timing: timing, autospace: autospace))
    var marks: [Mark] = []
    for (dit, dah, n) in script + [(false, false, tail)] {
        for _ in 0..<n {
            if let mark = keyer.tick(dit: dit, dah: dah).mark { marks.append(mark) }
        }
    }
    return marks
}

private func symbols(_ marks: [Mark]) -> String { String(marks.compactMap { $0.element?.symbol }) }

@Suite struct TimingTests {
    @Test func parisUnit() {
        #expect(abs(MorseTiming(characterWPM: 20).unit - 0.06) < 1e-12)
        #expect(MorseTiming(characterWPM: 20).letterGap == 3 * 0.06)
    }

    @Test func farnsworthStretchesOnlyTheGaps() {
        let t = MorseTiming(characterWPM: 18, effectiveWPM: 10)
        #expect(t.isFarnsworth)
        #expect(t.dit == 1.2 / 18)
        // PARIS takes 60 / 10 = 6 s: 31 character units plus 19 spacing units.
        let paris = 31 * t.unit + 19 * t.spacingUnit
        #expect(abs(paris - 6.0) < 1e-9)
    }

    @Test func effectiveFasterThanCharacterIsIgnored() {
        let t = MorseTiming(characterWPM: 15, effectiveWPM: 25)
        #expect(!t.isFarnsworth)
        #expect(t.spacingUnit == t.unit)
    }
}

@Suite struct KeyerTests {
    @Test func heldDitRepeatsWithElementGaps() {
        let marks = run(.iambicB, [(true, false, 550)])
        #expect(symbols(marks) == "...")
        #expect(marks.map(\.start) == [0, 200, 400])
        #expect(marks.allSatisfy { $0.length == 100 })
    }

    @Test func dahIsThreeUnits() {
        let marks = run(.iambicA, [(false, true, 50)])
        #expect(symbols(marks) == "-")
        #expect(marks[0].length == 300)
    }

    @Test func squeezeAlternates() {
        // Dit first, then both: dit dah dit dah ...
        let marks = run(.iambicA, [(true, false, 20), (true, true, 1100)])
        #expect(symbols(marks).hasPrefix(".-.-"))
    }

    @Test func modeBSendsOneMoreAfterSqueezeRelease() {
        // Squeeze, released during the first dah (dah runs 200...500).
        let script: [(Bool, Bool, Int)] = [(true, true, 300)]
        #expect(symbols(run(.iambicB, script)) == ".-.")
        #expect(symbols(run(.iambicA, script)) == ".-")
    }

    @Test func ditMemoryCatchesATapDuringADah() {
        // Dah held briefly, then a quick dit tap while the dah is still sounding.
        let script: [(Bool, Bool, Int)] = [(false, true, 50), (false, false, 50), (true, false, 30)]
        #expect(symbols(run(.iambicA, script)) == "-.")
        #expect(symbols(run(.iambicB, script)) == "-.")
    }

    @Test func straightKeyReportsUnlabelledMarks() {
        let marks = run(.straight, [(true, false, 120), (false, false, 80), (false, true, 330)])
        #expect(marks.map(\.length) == [120, 330])
        #expect(marks.allSatisfy { $0.element == nil })
    }

    @Test func autospaceHoldsANewCharacterToAFullLetterGap() {
        // E, then a second dit pressed 250 samples after the first ended (gap 100 + 150 idle).
        let script: [(Bool, Bool, Int)] = [(true, false, 50), (false, false, 300), (true, false, 50)]
        let plain = run(.iambicA, script)
        #expect(plain[1].start - plain[0].end == 250)
        let spaced = run(.iambicA, autospace: true, script)
        #expect(spaced[1].start - spaced[0].end == 300)
    }

    @Test func autospaceUsesFarnsworthGap() {
        let timing = MorseTiming(characterWPM: 12, effectiveWPM: 6)
        let letterGap = Int((timing.letterGap * rate).rounded())
        let script: [(Bool, Bool, Int)] = [(true, false, 50), (false, false, 300), (true, false, 50)]
        let marks = run(.iambicA, timing: timing, autospace: true, script, tail: 2000)
        #expect(marks[1].start - marks[0].end == letterGap)
    }
}

@Suite struct DecoderTests {
    private func decode(_ script: [(Bool, Bool, Int)], mode: KeyerMode = .iambicB,
                        timing: MorseTiming = twelve) -> String {
        var keyer = Keyer(sampleRate: rate, settings: .init(mode: mode, timing: timing))
        var decoder = Decoder(sampleRate: rate, timing: timing)
        for (dit, dah, n) in script + [(false, false, 2000)] {
            for _ in 0..<n {
                let out = keyer.tick(dit: dit, dah: dah)
                if let mark = out.mark { decoder.add(mark) }
                decoder.update(now: keyer.clock, keyDown: out.keyDown && out.mark == nil)
            }
        }
        return decoder.text
    }

    @Test func lettersAndWords() {
        // A (squeeze from dit), letter gap, N (squeeze from dah), word gap, E.
        let text = decode([
            (true, false, 20), (true, true, 280), (false, false, 500),
            (false, true, 20), (true, true, 380), (false, false, 900),
            (true, false, 50),
        ], mode: .iambicA)
        #expect(text == "AN E ")
    }

    @Test func straightKeyByLength() {
        let text = decode([(true, false, 300), (false, false, 100), (true, false, 100)], mode: .straight)
        #expect(text == "N ")
    }

    @Test func prosignsAreOverlined() {
        #expect(MorseCode.decode(".-.-.") == "A\u{0305}R\u{0305}")
        #expect(MorseCode.decode("-...-") == "B\u{0305}T\u{0305}")
    }
}

@Suite struct TextKeyingTests {
    @Test func tokensHandleProsignsAndSpaces() {
        let tokens = MorseCode.tokens(for: "e  t <ar>")
        #expect(tokens == [".", nil, "-", nil, ".-.-."])
    }

    @Test func farnsworthGapsInPlayback() {
        let timing = MorseTiming(characterWPM: 12, effectiveWPM: 6)
        let segments = TextKeying.segments(for: "EE", timing: timing, sampleRate: rate)
        let gap = Int((timing.letterGap * rate).rounded())
        #expect(segments.map(\.1) == [100, 100, gap, 100, 50])
        #expect(segments.map(\.0) == [false, true, false, true, false])
    }
}

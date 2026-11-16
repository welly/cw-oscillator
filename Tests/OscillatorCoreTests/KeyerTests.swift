import Foundation
import Testing
@testable import OscillatorCore

/// 1 kHz sample rate at 12 WPM: one unit is exactly 100 samples.
private let rate = 1000.0
private let twelve = MorseTiming(wpm: 12)

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
        let t = MorseTiming(wpm: 20)
        #expect(abs(t.unit - 0.06) < 1e-12)
        #expect(t.letterGap == 3 * t.unit)
        #expect(t.wordGap == 7 * t.unit)
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

    @Test func gapsBetweenCharactersAreMeasured() {
        var decoder = Decoder(sampleRate: rate, timing: twelve)
        // E, a 3.5-unit gap, T, a 5.5-unit gap, E, then a 20-unit pause and T.
        let marks = [Mark(start: 0, end: 100, element: .dit), Mark(start: 450, end: 750, element: .dah),
                     Mark(start: 1300, end: 1400, element: .dit), Mark(start: 3400, end: 3700, element: .dah)]
        var gaps: [CharacterGap?] = []
        for mark in marks {
            decoder.add(mark)
            decoder.update(now: mark.end + 1000)
            gaps.append(decoder.lastGap)
        }
        #expect(gaps[0] == nil)
        #expect(gaps[1]?.before == "E" && gaps[1]?.after == "T")
        #expect(abs((gaps[1]?.units ?? 0) - 3.5) < 1e-9)
        #expect(gaps[1]?.kind == .letter)
        #expect(gaps[2]?.before == "T" && gaps[2]?.after == "E")
        #expect(abs((gaps[2]?.units ?? 0) - 5.5) < 1e-9)
        #expect(gaps[2]?.kind == .word)
        #expect(gaps[3] == gaps[2]) // a long pause isn't counted
        #expect(decoder.text == "E T E T ")
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

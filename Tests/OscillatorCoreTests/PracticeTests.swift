import Foundation
import Testing
@testable import OscillatorCore

/// Sent characters with the given gaps (units) before each; nil for the first.
private func sent(_ items: [(String, Double?)]) -> [DecodedCharacter] {
    var t = 0
    return items.map { text, gap in
        t += Int((gap ?? 0) * 100)
        defer { t += 300 }
        return DecodedCharacter(text: text, start: t, end: t + 300, gapBefore: gap)
    }
}

@Suite struct PracticeTargetTests {
    @Test func parsesWordsAndProsigns() {
        let target = PracticeTarget("cq de  g3ajm <ar>")
        #expect(target.tokens.map(\.text) == ["C", "Q", "D", "E", "G", "3", "A", "J", "M", "A\u{0305}R\u{0305}"])
        #expect(target.tokens.map(\.startsWord) == [false, false, true, false, true, false, false, false, false, true])
        #expect(target.text == "CQ DE G3AJM A\u{0305}R\u{0305}")
    }

    @Test func randomCallsignsLookRight() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let call = PracticeGenerator.randomCallsign(using: &rng)
            #expect(call.range(of: #"^[A-Z0-9]{1,2}[0-9][A-Z]{1,3}(/P)?$"#, options: .regularExpression) != nil, "\(call)")
        }
    }

    @Test func everyBuiltInPhraseIsSendable() {
        let generator = PracticeGenerator(myCallsign: "G3AJM")
        for source in PracticeSource.allCases {
            for _ in 0..<30 { #expect(!generator.next(source).isEmpty) }
        }
        for phrase in PracticeGenerator.exchanges + PracticeGenerator.words {
            let raw = phrase.replacingOccurrences(of: "{CALL}", with: "").replacingOccurrences(of: "{OTHER}", with: "")
                .replacingOccurrences(of: "{RST}", with: "")
            let letters = raw.filter { !$0.isWhitespace && $0 != "<" && $0 != ">" }
            let target = PracticeTarget(raw)
            #expect(target.tokens.map(\.text).joined().count >= letters.count - 4, "\(phrase)")
        }
    }
}

@Suite struct AttemptResultTests {
    let target = PracticeTarget("G3 AB")

    @Test func perfect() {
        let result = AttemptResult(target: target, sent: sent([("G", nil), ("3", 3), ("A", 7), ("B", 3)]))
        #expect(result.isCorrect)
        #expect(result.gaps == [nil, .good, .good, .good])
    }

    @Test func longLetterGapIsAllowedButFlagged() {
        let result = AttemptResult(target: target, sent: sent([("G", nil), ("3", 4.5), ("A", 7), ("B", 3)]))
        #expect(result.isCorrect)
        #expect(result.longGaps == 1)
    }

    @Test func unwantedAndMissingSpaces() {
        let result = AttemptResult(target: target, sent: sent([("G", nil), ("3", 5.4), ("A", 3), ("B", 3)]))
        #expect(!result.isCorrect)
        #expect(result.gaps == [nil, .unwantedSpace, .missingSpace, .good])
        #expect(result.spacingErrors == 2)
    }

    @Test func wrongCharacter() {
        let result = AttemptResult(target: target, sent: sent([("G", nil), ("3", 3), ("N", 7), ("B", 3)]))
        #expect(result.characters == [.correct, .correct, .wrong("N"), .correct])
        #expect(result.characterErrors == 1)
    }

    @Test func missedCharacterDoesNotShiftTheRest() {
        let result = AttemptResult(target: target, sent: sent([("G", nil), ("A", 7), ("B", 3)]))
        #expect(result.characters == [.correct, .missing, .correct, .correct])
        #expect(result.gaps == [nil, nil, nil, .good])
    }

    @Test func extraCharacterIsCounted() {
        let result = AttemptResult(target: target, sent: sent([("G", nil), ("E", 3), ("3", 3), ("A", 7), ("B", 3)]))
        #expect(result.characters == [.correct, .correct, .correct, .correct])
        #expect(result.extra == ["E"])
        #expect(!result.isCorrect)
    }
}

@Suite struct DecodedCharacterTests {
    @Test func decoderKeepsCharactersWithTimes() {
        var decoder = Decoder(sampleRate: 1000, timing: MorseTiming(wpm: 12))
        decoder.add(Mark(start: 0, end: 300, element: .dah))
        decoder.add(Mark(start: 400, end: 500, element: .dit))
        decoder.add(Mark(start: 850, end: 950, element: .dit))
        decoder.update(now: 2000)
        #expect(decoder.characters == [
            DecodedCharacter(text: "N", code: "-.", start: 0, end: 500, gapBefore: nil),
            DecodedCharacter(text: "E", code: ".", start: 850, end: 950, gapBefore: 3.5),
        ])
    }
}

@Suite struct FarnsworthTests {
    @Test func spacingUnitFitsPARISAtTheEffectiveSpeed() {
        let t = MorseTiming(wpm: 18, effectiveWPM: 10)
        #expect(t.isFarnsworth)
        #expect(t.dit == 1.2 / 18)
        // PARIS takes 60 / 10 = 6 s: 31 character units plus 19 spacing units.
        #expect(abs(31 * t.unit + 19 * t.spacingUnit - 6.0) < 1e-9)
        #expect(t.letterGap == 3 * t.spacingUnit)
    }

    @Test func effectiveAtOrAboveCharacterSpeedIsPlain() {
        let t = MorseTiming(wpm: 15, effectiveWPM: 25)
        #expect(!t.isFarnsworth)
        #expect(t.spacingUnit == t.unit)
    }

    @Test func decoderMeasuresGapsInSpacingUnits() {
        // 12/6 WPM at 1 kHz: a dit is 100 samples, a spacing unit about 363.
        let timing = MorseTiming(wpm: 12, effectiveWPM: 6)
        let spacing = timing.spacingUnit * 1000
        var decoder = Decoder(sampleRate: 1000, timing: timing)
        decoder.add(Mark(start: 0, end: 100, element: .dit))
        // A 3-spacing-unit gap: a letter gap, not a word space, though it's ~11 dits long.
        let start = 100 + Int(3 * spacing)
        decoder.add(Mark(start: start, end: start + 300, element: .dah))
        decoder.update(now: start + 300 + Int(8 * spacing))
        #expect(decoder.text == "ET ")
        #expect(abs((decoder.characters[1].gapBefore ?? 0) - 3) < 0.01)
    }

    @Test func autospaceHoldsToTheFarnsworthLetterGap() {
        let timing = MorseTiming(wpm: 12, effectiveWPM: 6)
        var keyer = Keyer(sampleRate: 1000, settings: .init(mode: .iambicA, timing: timing, autospace: true))
        var marks: [Mark] = []
        for (dit, n) in [(true, 50), (false, 300), (true, 50), (false, 3000)] {
            for _ in 0..<n { if let m = keyer.tick(dit: dit, dah: false).mark { marks.append(m) } }
        }
        #expect(marks.count == 2)
        #expect(marks[1].start - marks[0].end == Int((timing.letterGap * 1000).rounded()))
    }
}

@Suite struct ErrorSignalTests {
    @Test func sixOrMoreDitsIsTheErrorSignal() {
        #expect(MorseCode.decode("........") == MorseCode.errorSignal)
        #expect(MorseCode.decode("......") == MorseCode.errorSignal)
        #expect(MorseCode.decode(".....") == "5")
        #expect(MorseCode.decode("....") == "H")
    }
}

@Suite struct ErrorRunTests {
    /// Characters with letter gaps (3) between them, or word gaps where `word` is set.
    private func chars(_ texts: [String], wordBefore: Set<Int> = []) -> [DecodedCharacter] {
        texts.enumerated().map { i, t in
            DecodedCharacter(text: t, start: i * 1000, end: i * 1000 + 500,
                             gapBefore: i == 0 ? nil : (wordBefore.contains(i) ? 7 : 3))
        }
    }

    @Test func eightCleanDits() {
        let target = PracticeTarget("DOG")
        #expect(ErrorSignal.find(in: chars(["D", MorseCode.errorSignal]), target: target)?.restartAt == 2)
    }

    @Test func ditsBrokenIntoLetters() {
        let target = PracticeTarget("DOG")
        #expect(ErrorSignal.find(in: chars(["D", "O", "S", "I", "E"]), target: target)?.restartAt == 5)
        #expect(ErrorSignal.find(in: chars(["D", "H", "I"]), target: target)?.restartAt == 3)
        #expect(ErrorSignal.find(in: chars(["D", "S", "I"]), target: target)?.restartAt == nil) // only 5 dits
    }

    @Test func realWordsMadeOfDitsAreNotErrors() {
        #expect(ErrorSignal.find(in: chars(["H", "I", "S"]), target: PracticeTarget("HIS"))?.restartAt == nil)
        #expect(ErrorSignal.find(in: chars(["S", "H", "E"]), target: PracticeTarget("SHE"))?.restartAt == nil)
        #expect(ErrorSignal.find(in: chars(["7", "3", "E", "S"]), target: PracticeTarget("73 ES"))?.restartAt == nil)
        // ...but the same dits where the target doesn't have them are.
        #expect(ErrorSignal.find(in: chars(["H", "I", "S", "S"]), target: PracticeTarget("HIS"))?.restartAt == 4)
    }

    @Test func aWordGapSplitsTheRun() {
        let target = PracticeTarget("DOG")
        #expect(ErrorSignal.find(in: chars(["S", "S"], wordBefore: [1]), target: target)?.restartAt == nil)
    }
}

@Suite struct ErrorRunOnTests {
    @Test func ditsRunOnFromAFumbledCharacter() {
        // "--." then eight dits with no letter gap: one long character.
        #expect(MorseCode.decode("--.........") == MorseCode.errorSignal)
        #expect(MorseCode.decode("-....") == "6") // a real character ending in four dits
        let target = PracticeTarget("DOG")
        let run = [
            DecodedCharacter(text: "D", code: "-..", start: 0, end: 500, gapBefore: nil),
            DecodedCharacter(text: "*", code: "---....", start: 1000, end: 1500, gapBefore: 3),
            DecodedCharacter(text: "I", code: "..", start: 2000, end: 2300, gapBefore: 3),
        ]
        #expect(ErrorSignal.find(in: run, target: target)?.restartAt == 3)
    }

    @Test func realKeyerAndDecoderEndToEnd() {
        let rate = 1000.0
        let timing = MorseTiming(wpm: 12)
        var keyer = Keyer(sampleRate: rate, settings: .init(mode: .iambicB, timing: timing))
        var decoder = Decoder(sampleRate: rate, timing: timing)
        // A dah, then the dit paddle held straight away for ten dits.
        for (dit, dah, n) in [(false, true, 50), (false, false, 300), (true, false, 1900), (false, false, 1000)] {
            for _ in 0..<n {
                let out = keyer.tick(dit: dit, dah: dah)
                if let m = out.mark { decoder.add(m) }
                decoder.update(now: keyer.clock, keyDown: out.keyDown && out.mark == nil)
            }
        }
        #expect(decoder.characters.last?.text == MorseCode.errorSignal)
        #expect(ErrorSignal.find(in: decoder.characters, target: PracticeTarget("DOG"))?.restartAt == decoder.characters.count)
    }
}

@Suite struct ErrorBurstTests {
    @Test func theWholeBurstIsSwallowed() {
        // S H then E E: the restart waits for the end, and covers all of it.
        let target = PracticeTarget("DOG")
        var t = 0
        let chars = ["D", "S", "H", "E", "E"].enumerated().map { i, text in
            defer { t += 1000 }
            return DecodedCharacter(text: text, start: t, end: t + 500, gapBefore: i == 0 ? nil : 3)
        }
        #expect(ErrorSignal.find(in: Array(chars.prefix(3)), target: target) == .init(restartAt: 3, atEnd: true))
        #expect(ErrorSignal.find(in: chars, target: target) == .init(restartAt: 5, atEnd: true))
    }

    @Test func ditsAfterACleanErrorSignalJoinTheBurst() {
        let target = PracticeTarget("DOG")
        let chars = [
            DecodedCharacter(text: "D", code: "-..", start: 0, end: 500, gapBefore: nil),
            DecodedCharacter(text: MorseCode.errorSignal, code: "........", start: 1000, end: 2500, gapBefore: 3),
            DecodedCharacter(text: "E", code: ".", start: 2800, end: 2900, gapBefore: 2.5),
        ]
        #expect(ErrorSignal.find(in: chars, target: target) == .init(restartAt: 3, atEnd: true))
    }

    @Test func aFreshStartAfterTheErrorSignalIsKept() {
        let target = PracticeTarget("DOG")
        let chars = [
            DecodedCharacter(text: MorseCode.errorSignal, code: "........", start: 0, end: 1500, gapBefore: nil),
            DecodedCharacter(text: "D", code: "-..", start: 2000, end: 2500, gapBefore: 3),
        ]
        #expect(ErrorSignal.find(in: chars, target: target) == .init(restartAt: 1, atEnd: false))
    }
}

@Suite struct StatisticsTests {
    private let timing = MorseTiming(wpm: 12) // a unit is 100 samples at 1 kHz

    /// Characters with the given codes, laid out with the given gaps (spacing units).
    private func sent(_ items: [(String, String, Double?)]) -> [DecodedCharacter] {
        var t = 0
        return items.map { text, code, gap in
            t += Int((gap ?? 0) * 100)
            let length = (code.reduce(0) { $0 + ($1 == "-" ? 3 : 1) } + code.count - 1) * 100
            defer { t += length }
            return DecodedCharacter(text: text, code: code, start: t, end: t + length, gapBefore: gap)
        }
    }

    @Test func perfectSpacingIsTheCharacterSpeed() {
        let s = sent([("A", ".-", nil), ("B", "-...", 3)])
        let wpm = PracticeStats.effectiveWPM(sent: s, timing: timing, sampleRate: 1000)
        #expect(abs((wpm ?? 0) - 12) < 1e-9)
    }

    @Test func longGapsLowerTheEffectiveSpeed() {
        // Characters 5 + 9 units; a 4.5-unit letter gap instead of 3 takes 18.5 units for 17.
        let s = sent([("A", ".-", nil), ("B", "-...", 4.5)])
        let wpm = PracticeStats.effectiveWPM(sent: s, timing: timing, sampleRate: 1000)
        #expect(abs((wpm ?? 0) - 12 * 17.0 / 18.5) < 1e-9)
    }

    @Test func recordsAccuracySpacingAndMisses() {
        var stats = PracticeStats()
        let target = PracticeTarget("AB C")
        let good = sent([("A", ".-", nil), ("B", "-...", 3), ("C", "-.-.", 7)])
        stats.record(target: target, result: AttemptResult(target: target, sent: good), sent: good,
                     timing: timing, sampleRate: 1000)
        let bad = sent([("A", ".-", nil), ("D", "-..", 4.5), ("C", "-.-.", 4)])
        stats.record(target: target, result: AttemptResult(target: target, sent: bad), sent: bad,
                     timing: timing, sampleRate: 1000)
        #expect(stats.attempts == 2)
        #expect(stats.correct == 1)
        #expect(stats.bestStreak == 1 && stats.streak == 0)
        #expect(stats.characters == 6 && stats.characterErrors == 1)
        #expect(stats.missed == ["B": 1])
        #expect(stats.letterGaps == [3, 4.5])
        #expect(stats.longLetterGaps == 1)
        #expect(stats.missingSpaces == 1)
        #expect(stats.averageLetterGap == 3.75)
        #expect(stats.history.map(\.correct) == [true, false])
    }
}

@Suite struct RecentSpeedTests {
    @Test func onlyAttemptsAtTheCurrentSettingsCount() {
        var stats = PracticeStats()
        let target = PracticeTarget("AB")
        func send(_ timing: MorseTiming, gap: Double) {
            let unit = timing.unit * 1000
            let a = DecodedCharacter(text: "A", code: ".-", start: 0, end: Int(5 * unit), gapBefore: nil)
            let bStart = Int((5 + gap) * unit)
            let b = DecodedCharacter(text: "B", code: "-...", start: bStart, end: bStart + Int(9 * unit), gapBefore: gap)
            stats.record(target: target, result: AttemptResult(target: target, sent: [a, b]), sent: [a, b],
                         timing: timing, sampleRate: 1000)
        }
        let slow = MorseTiming(wpm: 12), fast = MorseTiming(wpm: 20)
        send(slow, gap: 3)
        send(fast, gap: 3)
        send(fast, gap: 3)
        let recent = stats.recentEffectiveWPM(at: fast)
        #expect(recent?.attempts == 2)
        #expect(abs((recent?.wpm ?? 0) - 20) < 0.1)
        #expect(stats.recentEffectiveWPM(at: MorseTiming(wpm: 30)) == nil)
    }
}

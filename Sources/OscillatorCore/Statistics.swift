import Foundation

/// Running statistics for a practice session: accuracy, spacing and the speed you're really
/// sending at.
public struct PracticeStats: Equatable, Sendable {
    /// One finished attempt, for the history chart.
    public struct Attempt: Equatable, Sendable {
        public var correct: Bool
        /// Average letter gap in spacing units, if the attempt had any.
        public var averageLetterGap: Double?
        /// Effective speed in WPM, if it could be measured.
        public var effectiveWPM: Double?
        /// The speed settings it was sent at.
        public var timing: MorseTiming
    }

    public private(set) var attempts = 0
    public private(set) var correct = 0
    public private(set) var streak = 0
    public private(set) var bestStreak = 0
    /// Attempts started again with the error signal or Esc.
    public private(set) var restarts = 0
    /// Target characters attempted, and how many were wrong or missed.
    public private(set) var characters = 0
    public private(set) var characterErrors = 0
    /// Extra characters sent that weren't in the target.
    public private(set) var extraCharacters = 0
    /// Every judged letter gap and word gap, in spacing units.
    public private(set) var letterGaps: [Double] = []
    public private(set) var wordGaps: [Double] = []
    public private(set) var longLetterGaps = 0
    public private(set) var unwantedSpaces = 0
    public private(set) var missingSpaces = 0
    /// Target characters sent wrongly or missed, and how often.
    public private(set) var missed: [String: Int] = [:]
    public private(set) var history: [Attempt] = []

    public init() {}

    public var accuracy: Double? { attempts == 0 ? nil : Double(correct) / Double(attempts) }
    public var characterAccuracy: Double? {
        characters == 0 ? nil : Double(characters - characterErrors) / Double(characters)
    }
    public var averageLetterGap: Double? { Self.mean(letterGaps) }
    /// Standard deviation of the letter gaps: how consistent your spacing is.
    public var letterGapSpread: Double? { Self.standardDeviation(letterGaps) }
    public var averageWordGap: Double? { Self.mean(wordGaps) }
    /// Your sending speed over your most recent attempts at these speed settings (so changing
    /// speed starts it afresh rather than mixing speeds), and how many attempts that covers.
    public func recentEffectiveWPM(at timing: MorseTiming, count: Int = 5) -> (wpm: Double, attempts: Int)? {
        let speeds = history.reversed().filter { $0.timing == timing }.compactMap(\.effectiveWPM).prefix(count)
        guard let mean = Self.mean(Array(speeds)) else { return nil }
        return (mean, speeds.count)
    }

    /// The characters you get wrong most, most first.
    public func mostMissed(_ count: Int = 5) -> [(String, Int)] {
        missed.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(count).map { ($0.key, $0.value) }
    }

    public mutating func recordRestart() { restarts += 1 }

    /// Adds a finished attempt.
    public mutating func record(target: PracticeTarget, result: AttemptResult, sent: [DecodedCharacter],
                                timing: MorseTiming, sampleRate: Double) {
        attempts += 1
        if result.isCorrect {
            correct += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
        } else {
            streak = 0
        }
        characters += target.count
        characterErrors += result.characters.filter { $0 != .correct }.count
        extraCharacters += result.extra.count
        for (token, status) in zip(target.tokens, result.characters) where status != .correct {
            missed[token.text, default: 0] += 1
        }

        var attemptLetterGaps: [Double] = []
        for (k, token) in target.tokens.enumerated() {
            guard let units = result.gapUnits[k], let status = result.gaps[k] else { continue }
            if token.startsWord {
                wordGaps.append(units)
                if status == .missingSpace { missingSpaces += 1 }
            } else {
                letterGaps.append(units)
                attemptLetterGaps.append(units)
                if status == .long { longLetterGaps += 1 }
                if status == .unwantedSpace { unwantedSpaces += 1 }
            }
        }

        history.append(Attempt(correct: result.isCorrect,
                               averageLetterGap: Self.mean(attemptLetterGaps),
                               effectiveWPM: Self.effectiveWPM(sent: sent, timing: timing, sampleRate: sampleRate),
                               timing: timing))
    }

    /// The speed your sending works out at: the character speed, scaled by how long the
    /// characters and gaps you sent would take with standard spacing against how long they
    /// actually took. The keyer times the characters, so the difference is all in your spacing.
    public static func effectiveWPM(sent: [DecodedCharacter], timing: MorseTiming, sampleRate: Double) -> Double? {
        guard sent.count >= 2, let first = sent.first, let last = sent.last else { return nil }
        var units = 0.0
        for (i, character) in sent.enumerated() {
            guard !character.code.isEmpty else { return nil }
            units += character.code.reduce(0.0) { $0 + ($1 == "-" ? 3 : 1) } + Double(character.code.count - 1)
            if i > 0 {
                let gap = character.gapBefore ?? Decoder.longestMeasuredGap + 1
                units += gap >= Decoder.wordGapUnits ? 7 : 3
            }
        }
        let actual = Double(last.end - first.start) / sampleRate
        guard actual > 0 else { return nil }
        return timing.wpm * units * timing.unit / actual
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let m = mean(values) else { return nil }
        return (values.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(values.count - 1)).squareRoot()
    }
}

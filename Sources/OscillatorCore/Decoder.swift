import Foundation

/// The silence between two characters, for showing the operator how their spacing is going.
public struct CharacterGap: Equatable, Sendable {
    public enum Kind: Sendable {
        /// Up to 4 units: a good letter gap (3 is perfect).
        case letter
        /// 4 to 5 units: still read as a letter gap, but drifting towards a word space.
        case longLetter
        /// 5 units or more: read as a word space.
        case word

        public init(units: Double) {
            self = units >= Decoder.wordGapUnits ? .word : units >= Decoder.longLetterGapUnits ? .longLetter : .letter
        }
    }

    public var before: String
    public var after: String
    /// Length in spacing units (dit lengths, or the stretched unit with Farnsworth).
    public var units: Double

    public var kind: Kind { Kind(units: units) }
}

/// One decoded character and when it was sent.
public struct DecodedCharacter: Equatable, Sendable {
    /// The character, e.g. "G", or "A̅R̅" for a prosign; "*" when the pattern isn't known.
    public var text: String
    /// What was sent, e.g. "--.".
    public var code: String
    /// Start of its first element and end of its last, in samples on the keyer's clock.
    public var start: Int
    public var end: Int
    /// Silence before it in spacing units, or nil for the first character (or after a pause of over
    /// 10 units, which is a break rather than spacing).
    public var gapBefore: Double?

    public init(text: String, code: String = "", start: Int, end: Int, gapBefore: Double?) {
        self.text = text
        self.code = code
        self.start = start
        self.end = end
        self.gapBefore = gapBefore
    }
}

/// Turns the marks the keyer sends into text.
///
/// Keyed elements arrive already labelled; straight-key marks are judged by length (over two
/// units is a dah). A gap of two units (at the character speed) ends a character. Gaps between
/// characters are measured in spacing units, which Farnsworth stretches, so a letter gap is
/// always 3 and a word gap 7; past the midpoint, 5, ends a word.
public struct Decoder: Sendable {
    public var timing: MorseTiming
    public let sampleRate: Double

    /// The decoded text so far.
    public private(set) var text = ""
    /// Dits and dahs of the character being sent, e.g. ".-".
    public private(set) var pending = ""
    /// Every character decoded since the last clear, in order.
    public private(set) var characters: [DecodedCharacter] = []
    /// The most recent gap between two characters (pauses over 10 units aren't counted).
    public private(set) var lastGap: CharacterGap?
    /// End of the last mark, in samples.
    public private(set) var lastEnd: Int?
    private var pendingStart = 0
    private var spaceAdded = true
    private var lastCharacter: String?
    /// Gap in units before the character being sent, when there was a character before it.
    private var gapBeforePending: Double?

    /// Gaps of this many units or more end a word.
    public static let wordGapUnits = 5.0
    /// Letter gaps of this many units or more are flagged as long.
    public static let longLetterGapUnits = 4.0
    /// Pauses longer than this are breaks, not spacing.
    public static let longestMeasuredGap = 10.0

    public init(sampleRate: Double, timing: MorseTiming) {
        self.sampleRate = sampleRate
        self.timing = timing
    }

    private var letterThreshold: Double { 2 * timing.unit }
    private var wordThreshold: Double { Self.wordGapUnits * timing.spacingUnit }

    public mutating func add(_ mark: Mark) {
        update(now: mark.start)
        if pending.isEmpty, let lastEnd, lastCharacter != nil {
            let units = Double(mark.start - lastEnd) / sampleRate / timing.spacingUnit
            gapBeforePending = units <= Self.longestMeasuredGap ? units : nil
        }
        if pending.isEmpty { pendingStart = mark.start }
        let element = mark.element
            ?? (Double(mark.length) / sampleRate > 2 * timing.unit ? .dah : .dit)
        pending.append(element.symbol)
        lastEnd = mark.end
        spaceAdded = false
    }

    /// Closes the current character or word once enough silence has passed. While the key is
    /// down nothing closes: the next mark's start gives the real gap.
    public mutating func update(now: Int, keyDown: Bool = false) {
        guard let lastEnd, !keyDown else { return }
        let gap = Double(now - lastEnd) / sampleRate
        if !pending.isEmpty && gap >= letterThreshold {
            let character = MorseCode.decode(pending) ?? "*"
            text += character
            characters.append(DecodedCharacter(text: character, code: pending, start: pendingStart, end: lastEnd,
                                               gapBefore: lastCharacter == nil ? nil : gapBeforePending))
            pending = ""
            if let units = gapBeforePending, let before = lastCharacter {
                lastGap = CharacterGap(before: before, after: character, units: units)
            }
            gapBeforePending = nil
            lastCharacter = character
        }
        if !spaceAdded && pending.isEmpty && gap >= wordThreshold {
            if !text.isEmpty { text += " " }
            spaceAdded = true
        }
    }

    public mutating func clear() {
        text = ""
        pending = ""
        lastEnd = nil
        spaceAdded = true
        lastGap = nil
        characters = []
        lastCharacter = nil
        gapBeforePending = nil
    }
}

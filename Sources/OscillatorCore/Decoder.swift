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
    }

    public var before: String
    public var after: String
    /// Length in units (dit lengths).
    public var units: Double

    public var kind: Kind {
        units >= Decoder.wordGapUnits ? .word : units >= 4 ? .longLetter : .letter
    }
}

/// Turns the marks the keyer sends into text.
///
/// Keyed elements arrive already labelled; straight-key marks are judged by length (over two
/// units is a dah). A gap of two units or more ends a character; a gap past the midpoint between
/// a letter gap and a word gap ends a word.
public struct Decoder: Sendable {
    public var timing: MorseTiming
    public let sampleRate: Double

    /// The decoded text so far.
    public private(set) var text = ""
    /// Dits and dahs of the character being sent, e.g. ".-".
    public private(set) var pending = ""
    /// The most recent gap between two characters (pauses over 10 units aren't counted).
    public private(set) var lastGap: CharacterGap?
    private var lastEnd: Int?
    private var spaceAdded = true
    private var lastCharacter: String?
    /// Gap in units before the character being sent, when there was a character before it.
    private var gapBeforePending: Double?

    /// Gaps of this many units or more end a word.
    public static let wordGapUnits = 5.0
    private static let longestMeasuredGap = 10.0

    public init(sampleRate: Double, timing: MorseTiming) {
        self.sampleRate = sampleRate
        self.timing = timing
    }

    private var letterThreshold: Double { 2 * timing.unit }
    private var wordThreshold: Double { Self.wordGapUnits * timing.unit }

    public mutating func add(_ mark: Mark) {
        update(now: mark.start)
        if pending.isEmpty, let lastEnd, lastCharacter != nil {
            let units = Double(mark.start - lastEnd) / sampleRate / timing.unit
            gapBeforePending = units <= Self.longestMeasuredGap ? units : nil
        }
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
        lastCharacter = nil
        gapBeforePending = nil
    }
}

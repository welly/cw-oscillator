import Foundation

/// Turns the marks the keyer sends into text.
///
/// Keyed elements arrive already labelled; straight-key marks are judged by length (over two
/// units is a dah). A gap of two units or more ends a character; a gap past the midpoint between
/// a letter gap and a word gap (at the Farnsworth spacing when that's on) ends a word.
public struct Decoder: Sendable {
    public var timing: MorseTiming
    public let sampleRate: Double

    /// The decoded text so far.
    public private(set) var text = ""
    /// Dits and dahs of the character being sent, e.g. ".-".
    public private(set) var pending = ""
    private var lastEnd: Int?
    private var spaceAdded = true

    public init(sampleRate: Double, timing: MorseTiming) {
        self.sampleRate = sampleRate
        self.timing = timing
    }

    private var letterThreshold: Double { 2 * timing.unit }
    private var wordThreshold: Double { max(letterThreshold + timing.unit, 5 * timing.spacingUnit) }

    public mutating func add(_ mark: Mark) {
        update(now: mark.start)
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
            text += MorseCode.decode(pending) ?? "*"
            pending = ""
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
    }
}

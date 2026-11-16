import Foundation

/// Morse timing from a character speed and an optional Farnsworth (effective) speed.
///
/// PARIS timing: one unit is 1.2 / WPM seconds. With Farnsworth, characters are sent at the
/// character speed and the gaps between characters and words are stretched so that the overall
/// rate is the effective speed (ARRL formula: the 19 spacing units in PARIS absorb the extra time).
public struct MorseTiming: Equatable, Sendable {
    /// Character speed in WPM: sets the length of dits, dahs and the gaps inside a character.
    public var characterWPM: Double
    /// Effective speed in WPM. Equal to (or above) `characterWPM` means no Farnsworth stretching.
    public var effectiveWPM: Double

    public init(characterWPM: Double, effectiveWPM: Double? = nil) {
        self.characterWPM = max(1, characterWPM)
        self.effectiveWPM = max(1, effectiveWPM ?? characterWPM)
    }

    /// True when the gaps are stretched.
    public var isFarnsworth: Bool { effectiveWPM < characterWPM }

    /// One unit at the character speed, in seconds: a dit, and the gap between elements.
    public var unit: Double { 1.2 / characterWPM }
    public var dit: Double { unit }
    public var dah: Double { 3 * unit }
    public var elementGap: Double { unit }

    /// One spacing unit for the gaps between characters and words, in seconds.
    public var spacingUnit: Double {
        guard isFarnsworth else { return unit }
        let c = characterWPM, s = effectiveWPM
        let totalDelay = (60 * c - 37.2 * s) / (s * c)
        return totalDelay / 19
    }

    /// Gap between characters (3 spacing units).
    public var letterGap: Double { 3 * spacingUnit }
    /// Gap between words (7 spacing units).
    public var wordGap: Double { 7 * spacingUnit }
}

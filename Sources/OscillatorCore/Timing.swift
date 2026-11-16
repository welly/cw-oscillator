import Foundation

/// Morse timing from a speed in WPM (PARIS: one unit is 1.2 / WPM seconds).
public struct MorseTiming: Equatable, Sendable {
    public var wpm: Double

    public init(wpm: Double) {
        self.wpm = max(1, wpm)
    }

    /// One unit, in seconds: a dit, and the gap between elements.
    public var unit: Double { 1.2 / wpm }
    public var dit: Double { unit }
    public var dah: Double { 3 * unit }
    public var elementGap: Double { unit }
    /// Gap between characters (3 units).
    public var letterGap: Double { 3 * unit }
    /// Gap between words (7 units).
    public var wordGap: Double { 7 * unit }
}

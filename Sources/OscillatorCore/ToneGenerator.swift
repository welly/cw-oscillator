import Foundation

/// A sine oscillator with a raised-cosine envelope, so keying makes no clicks.
public struct ToneGenerator: Sendable {
    public let sampleRate: Double
    public var frequency: Double
    /// Output level, 0...1.
    public var volume: Double
    /// Rise and fall time in seconds.
    public var rampTime: Double {
        didSet { rampSamples = max(1, Int(rampTime * sampleRate)) }
    }

    private var phase = 0.0
    private var envelopePosition = 0
    private var rampSamples: Int

    public init(sampleRate: Double, frequency: Double = 600, volume: Double = 0.5, rampTime: Double = 0.005) {
        self.sampleRate = sampleRate
        self.frequency = frequency
        self.volume = volume
        self.rampTime = rampTime
        self.rampSamples = max(1, Int(rampTime * sampleRate))
    }

    /// The next sample with the key up or down.
    public mutating func next(keyDown: Bool) -> Float {
        if keyDown {
            if envelopePosition < rampSamples { envelopePosition += 1 }
        } else if envelopePosition > 0 {
            envelopePosition -= 1
        }
        guard envelopePosition > 0 else {
            phase = 0 // start each mark at a zero crossing
            return 0
        }
        let x = Double(envelopePosition) / Double(rampSamples)
        let s = sin(.pi / 2 * x)
        let envelope = s * s
        let value = sin(2 * .pi * phase) * envelope * volume
        phase += frequency / sampleRate
        if phase >= 1 { phase -= 1 }
        return Float(value)
    }
}

/// Key-down/key-up periods for practice text, at the character speed with Farnsworth gaps.
public enum TextKeying {
    /// (key down?, length in samples) segments. Starts with a short silence.
    public static func segments(for text: String, timing: MorseTiming, sampleRate: Double) -> [(Bool, Int)] {
        func n(_ seconds: Double) -> Int { max(1, Int((seconds * sampleRate).rounded())) }
        var result: [(Bool, Int)] = [(false, n(0.1))]
        var previousWasChar = false
        for token in MorseCode.tokens(for: text) {
            guard let code = token else {
                result.append((false, n(timing.wordGap)))
                previousWasChar = false
                continue
            }
            if previousWasChar { result.append((false, n(timing.letterGap))) }
            for (i, symbol) in code.enumerated() {
                if i > 0 { result.append((false, n(timing.elementGap))) }
                result.append((true, n(symbol == "." ? timing.dit : timing.dah)))
            }
            previousWasChar = true
        }
        result.append((false, n(0.05)))
        return result
    }
}

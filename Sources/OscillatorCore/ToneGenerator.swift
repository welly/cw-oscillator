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

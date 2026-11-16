import Foundation

public enum KeyerMode: String, CaseIterable, Identifiable, Sendable {
    case iambicA, iambicB, straight

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .iambicA: "Iambic A"
        case .iambicB: "Iambic B"
        case .straight: "Straight key"
        }
    }
}

/// One finished key-down period, in samples on the keyer's clock.
public struct Mark: Equatable, Sendable {
    public var start: Int
    public var end: Int
    /// The element the keyer sent, or nil for a straight key (the decoder judges it by length).
    public var element: Element?

    public init(start: Int, end: Int, element: Element?) {
        self.start = start
        self.end = end
        self.element = element
    }

    public var length: Int { end - start }
}

/// An electronic keyer that runs one step per audio sample, so element timing is exact.
///
/// Iambic A and B both have dit/dah memory: a tap of the other paddle during an element is sent
/// after it. They differ when a squeeze is released: B sends one more (opposite) element, A stops.
public struct Keyer: Sendable {
    public struct Settings: Equatable, Sendable {
        public var mode: KeyerMode
        public var timing: MorseTiming
        /// Holds a new character back until a full letter gap has passed, once the operator
        /// has paused longer than an element gap.
        public var autospace: Bool

        public init(mode: KeyerMode = .iambicB, timing: MorseTiming = MorseTiming(wpm: 20),
                    autospace: Bool = false) {
            self.mode = mode
            self.timing = timing
            self.autospace = autospace
        }
    }

    public struct Output: Equatable, Sendable {
        /// Whether the tone should sound for this sample.
        public var keyDown: Bool
        /// A key-down period that ended on this sample.
        public var mark: Mark?
    }

    private enum State: Equatable {
        case idle
        case element(Element, remaining: Int)
        case gap(remaining: Int)
        /// Autospace: waiting out the rest of a letter gap before sending `next`.
        case hold(Element, remaining: Int)
    }

    public var settings: Settings
    public let sampleRate: Double

    /// Samples since the keyer started.
    public private(set) var clock = 0
    private var state = State.idle
    private var memory: Element?
    private var last: Element = .dah
    private var markStart = 0
    /// Samples since the last element's trailing gap ended (only counted while idle).
    private var idleSamples = Int.max / 2
    private var straightDown = false

    public init(sampleRate: Double, settings: Settings = Settings()) {
        self.sampleRate = sampleRate
        self.settings = settings
    }

    public var isIdle: Bool {
        settings.mode == .straight ? !straightDown : state == .idle && memory == nil
    }

    private func samples(_ seconds: Double) -> Int { max(1, Int((seconds * sampleRate).rounded())) }

    /// Advances one sample with the paddles as they are now.
    public mutating func tick(dit: Bool, dah: Bool) -> Output {
        defer { clock += 1 }
        if settings.mode == .straight {
            return tickStraight(down: dit || dah)
        }
        if straightDown { // mode changed mid-mark
            straightDown = false
        }

        switch state {
        case .idle:
            let next: Element? = memory ?? (dit ? .dit : dah ? .dah : nil)
            guard let next else {
                if idleSamples < Int.max / 2 { idleSamples += 1 }
                return Output(keyDown: false, mark: nil)
            }
            memory = nil
            if settings.autospace {
                let timing = settings.timing
                let sinceElement = samples(timing.elementGap) + idleSamples
                let letterGap = samples(timing.letterGap)
                if sinceElement > samples(2 * timing.unit) && sinceElement < letterGap {
                    state = .hold(next, remaining: letterGap - sinceElement)
                    return tickHold()
                }
            }
            start(next, at: clock)
            return tickElement(dit: dit, dah: dah)
        case .element:
            return tickElement(dit: dit, dah: dah)
        case .gap(let remaining):
            latchMemory(current: last, dit: dit, dah: dah)
            if remaining > 1 {
                state = .gap(remaining: remaining - 1)
            } else {
                let next: Element?
                if let m = memory {
                    next = m
                } else if dit && dah {
                    next = last.opposite
                } else if dit {
                    next = .dit
                } else if dah {
                    next = .dah
                } else {
                    next = nil
                }
                memory = nil
                if let next {
                    start(next, at: clock + 1) // sounds from the next sample
                } else {
                    state = .idle
                    idleSamples = 0
                }
            }
            return Output(keyDown: false, mark: nil)
        case .hold:
            return tickHold()
        }
    }

    /// Clears any element in progress and the memory (for example when the window loses focus).
    public mutating func reset() {
        state = .idle
        memory = nil
        straightDown = false
        idleSamples = Int.max / 2
    }

    private mutating func start(_ element: Element, at sample: Int) {
        let length = element == .dit ? settings.timing.dit : settings.timing.dah
        state = .element(element, remaining: samples(length))
        markStart = sample
    }

    private mutating func tickElement(dit: Bool, dah: Bool) -> Output {
        guard case .element(let element, let remaining) = state else {
            return Output(keyDown: false, mark: nil)
        }
        latchMemory(current: element, dit: dit, dah: dah)
        if remaining > 1 {
            state = .element(element, remaining: remaining - 1)
            return Output(keyDown: true, mark: nil)
        }
        last = element
        state = .gap(remaining: samples(settings.timing.elementGap))
        return Output(keyDown: true, mark: Mark(start: markStart, end: clock + 1, element: element))
    }

    private mutating func tickHold() -> Output {
        guard case .hold(let next, let remaining) = state else { return Output(keyDown: false, mark: nil) }
        if remaining > 1 {
            state = .hold(next, remaining: remaining - 1)
        } else {
            start(next, at: clock + 1)
        }
        return Output(keyDown: false, mark: nil)
    }

    /// Remembers a press of the paddle opposite `current`.
    private mutating func latchMemory(current: Element, dit: Bool, dah: Bool) {
        let opposite = current.opposite
        let oppositeDown = opposite == .dit ? dit : dah
        let currentDown = current == .dit ? dit : dah
        guard oppositeDown else { return }
        switch settings.mode {
        case .iambicB:
            memory = opposite
        case .iambicA:
            // A squeeze (both held) alternates while it's held but leaves nothing behind when
            // released; a separate tap of the other paddle is still remembered.
            if !currentDown { memory = opposite }
        case .straight:
            break
        }
    }

    private mutating func tickStraight(down: Bool) -> Output {
        state = .idle
        memory = nil
        if down && !straightDown {
            straightDown = true
            markStart = clock
            return Output(keyDown: true, mark: nil)
        }
        if !down && straightDown {
            straightDown = false
            return Output(keyDown: false, mark: Mark(start: markStart, end: clock, element: nil))
        }
        return Output(keyDown: down, mark: nil)
    }
}

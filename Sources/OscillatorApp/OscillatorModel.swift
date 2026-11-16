import AppKit
import Observation
import OscillatorAudio
import OscillatorCore

/// What the timing strip draws. Kept apart from the main model because it changes every frame,
/// so only the strip redraws that often.
@MainActor
@Observable
final class TimingStripState {
    /// Now, in samples on the keyer's clock.
    var clock = 0
    /// Samples per spacing unit (the stretched unit with Farnsworth): gap lengths are in these.
    var spacingSamples = 2880.0
    /// Samples per unit at the effective speed: sets how much time the strip shows.
    var scaleSamples = 2880.0
    /// Recent marks (key-down periods).
    var marks: [Mark] = []
    /// Recent decoded characters, for the letters and gap lengths.
    var characters: [DecodedCharacter] = []
    /// When the key went down, if it's down now (to within one frame).
    var keyDownSince: Int?
    /// End of the last mark, for the live gap.
    var lastEnd: Int?
    /// Dits and dahs of a character still being sent (so the live gap isn't a character gap yet).
    var pending = ""
}

/// Free sending is a plain practice oscillator: hear your key, see what you sent. Practice gives
/// you targets and judges them.
enum SendingMode: String, CaseIterable, Identifiable {
    case free, practice

    var id: String { rawValue }
    var label: String { self == .free ? "Free" : "Practice" }
}

/// The app's settings and live state. Settings are kept in UserDefaults.
@MainActor
@Observable
final class OscillatorModel {
    // MARK: Settings

    var frequency: Double { didSet { save() } }
    var volume: Double { didSet { save() } }
    var wpm: Double { didSet { if effectiveWPM > wpm { effectiveWPM = wpm }; save() } }
    var farnsworth: Bool { didSet { save() } }
    var effectiveWPM: Double { didSet { save() } }
    var mode: KeyerMode { didSet { save() } }
    var reversePaddles: Bool { didSet { save() } }
    var autospace: Bool { didSet { save() } }
    var myCallsign: String {
        didSet {
            // Only callsign characters, so the target is always something sendable.
            let cleaned = Self.cleanCallsign(myCallsign)
            if cleaned != myCallsign {
                myCallsign = cleaned
                return
            }
            save()
            if practiceSource == .myCallsign { nextTarget() }
        }
    }
    var sendingMode: SendingMode = .practice {
        didSet {
            save()
            // Anything sent in free mode doesn't count towards the first target.
            if sendingMode == .practice { startAttempt() }
        }
    }
    var practiceSource: PracticeSource {
        didSet {
            save()
            nextTarget()
        }
    }

    // MARK: Live state

    private(set) var ditPressed = false
    private(set) var dahPressed = false
    private(set) var keyDown = false
    private(set) var copiedText = ""
    private(set) var pendingCode = ""
    var audioError: String?
    let strip = TimingStripState()

    // MARK: Practice

    private(set) var target = PracticeTarget("")
    /// Characters sent so far in this attempt.
    private(set) var attemptSent: [DecodedCharacter] = []
    /// The finished attempt, shown until the next one starts.
    private(set) var result: AttemptResult?
    /// What was copied in the finished attempt.
    private(set) var resultText = ""
    /// This session's statistics (since the app opened, or since they were reset).
    private(set) var stats = PracticeStats()
    /// Correct attempts in a row.
    var streak: Int { stats.streak }
    /// True just after the attempt was restarted (error signal or Esc), until you send again.
    private(set) var restarted = false
    /// Index into the decoder's characters where the current attempt starts.
    private var attemptStart = 0
    /// After a correct attempt, when to move on to a new target.
    private var advanceAt: Date?

    var timing: MorseTiming {
        MorseTiming(wpm: wpm, effectiveWPM: farnsworth ? min(effectiveWPM, wpm) : nil)
    }

    /// "20 WPM", or "20/10 WPM" with Farnsworth.
    var speedLabel: String {
        timing.isFarnsworth ? "\(Int(wpm))/\(Int(timing.effectiveWPM)) WPM" : "\(Int(wpm)) WPM"
    }

    private let defaults = UserDefaults.standard
    private let engine = OscillatorEngine()
    private let paddles = PaddleInput()
    private var decoder: Decoder
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var keyDownSince: Int?

    /// An attempt that stops short ends after this much silence (20 units, or 12 spacing
    /// units with Farnsworth if that's longer).
    private var attemptTimeout: Double { max(20 * timing.unit, 12 * timing.spacingUnit) }
    /// How much history the timing strip keeps.
    private static let stripHistoryUnits = 200.0

    init() {
        defaults.register(defaults: [
            "frequency": 600.0, "volume": 0.5, "wpm": 20.0, "farnsworth": false, "effectiveWPM": 10.0,
            "mode": KeyerMode.iambicB.rawValue, "reversePaddles": false,
            "autospace": false, "myCallsign": "",
            "practiceSource": PracticeSource.myCallsign.rawValue, "sendingMode": SendingMode.practice.rawValue,
        ])
        frequency = defaults.double(forKey: "frequency")
        volume = defaults.double(forKey: "volume")
        wpm = defaults.double(forKey: "wpm")
        farnsworth = defaults.bool(forKey: "farnsworth")
        effectiveWPM = defaults.double(forKey: "effectiveWPM")
        mode = KeyerMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .iambicB
        reversePaddles = defaults.bool(forKey: "reversePaddles")
        autospace = defaults.bool(forKey: "autospace")
        myCallsign = Self.cleanCallsign(defaults.string(forKey: "myCallsign") ?? "")
        practiceSource = PracticeSource(rawValue: defaults.string(forKey: "practiceSource") ?? "") ?? .myCallsign
        sendingMode = SendingMode(rawValue: defaults.string(forKey: "sendingMode") ?? "") ?? .practice
        decoder = Decoder(sampleRate: 48_000, timing: MorseTiming(wpm: 20))
        target = PracticeGenerator(myCallsign: myCallsign).next(practiceSource)
    }

    func start() {
        pushSettings()
        do {
            try engine.start()
        } catch {
            audioError = "Couldn't start audio: \(error.localizedDescription)"
        }
        decoder = Decoder(sampleRate: engine.sampleRate, timing: timing)

        paddles.onChange = { [weak self] dit, dah in self?.setPaddles(dit: dit, dah: dah) }
        paddles.start()

        // Losing focus means key-up events go elsewhere: let go rather than key forever.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseAll() }
        })

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func clearCopy() {
        decoder.clear()
        copiedText = ""
        pendingCode = ""
        strip.marks = []
        strip.characters = []
        strip.lastEnd = nil
        attemptStart = 0
        attemptSent = []
    }

    static func cleanCallsign(_ text: String) -> String {
        String(text.uppercased().filter { ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "/" })
    }

    func resetStats() { stats = PracticeStats() }

    /// A new target from the chosen source.
    func nextTarget() {
        target = PracticeGenerator(myCallsign: myCallsign).next(practiceSource, avoiding: target.text)
        startAttempt()
    }

    /// Clears the result and starts counting characters for the current target from now.
    private func startAttempt(at index: Int? = nil) {
        attemptStart = index ?? decoder.characters.count
        attemptSent = []
        result = nil
        resultText = ""
        advanceAt = nil
        restarted = false
    }

    /// Throws away the attempt in progress (or a wrong result) and starts the same target again.
    /// Esc does this; so does sending the error signal.
    func restartAttempt() {
        guard advanceAt == nil else { return } // a correct attempt is already moving on
        if !attemptSent.isEmpty { stats.recordRestart() }
        startAttempt()
        restarted = true
    }

    private func setPaddles(dit: Bool, dah: Bool) {
        let (d, a) = reversePaddles ? (dah, dit) : (dit, dah)
        ditPressed = d
        dahPressed = a
        engine.setPaddles(dit: d, dah: a)
    }

    private func releaseAll() {
        paddles.releaseAll()
        engine.releaseAll()
    }

    private func tick() {
        let (marks, status) = engine.poll()
        if decoder.sampleRate != engine.sampleRate {
            clearCopy()
            decoder = Decoder(sampleRate: engine.sampleRate, timing: timing)
        }
        decoder.timing = timing
        for mark in marks { decoder.add(mark) }
        decoder.update(now: status.clock, keyDown: status.keyDown)

        if keyDown != status.keyDown { keyDown = status.keyDown }
        if copiedText != decoder.text { copiedText = decoder.text }
        if pendingCode != decoder.pending { pendingCode = decoder.pending }

        updateStrip(newMarks: marks, clock: status.clock, keyDown: status.keyDown)
        updateAttempt(clock: status.clock, keyDown: status.keyDown)
    }

    private func updateStrip(newMarks: [Mark], clock: Int, keyDown: Bool) {
        let scaleSamples = engine.sampleRate * 1.2 / timing.effectiveWPM
        let oldest = clock - Int(Self.stripHistoryUnits * scaleSamples)
        if keyDown {
            if keyDownSince == nil { keyDownSince = clock }
        } else {
            keyDownSince = nil
        }
        strip.clock = clock
        strip.spacingSamples = engine.sampleRate * timing.spacingUnit
        strip.scaleSamples = scaleSamples
        strip.keyDownSince = keyDownSince
        strip.lastEnd = decoder.lastEnd
        if strip.pending != decoder.pending { strip.pending = decoder.pending }
        if !newMarks.isEmpty || strip.marks.first.map({ $0.end < oldest }) == true {
            strip.marks = (strip.marks + newMarks).filter { $0.end >= oldest }
        }
        if strip.characters.last != decoder.characters.last || strip.characters.first.map({ $0.end < oldest }) == true {
            strip.characters = decoder.characters.suffix(40).filter { $0.end >= oldest }
        }
    }

    private func updateAttempt(clock: Int, keyDown: Bool) {
        if let advanceAt {
            if Date() >= advanceAt { nextTarget() }
            return
        }
        guard sendingMode == .practice, !target.isEmpty else { return }
        let characters = decoder.characters
        if attemptStart > characters.count { attemptStart = characters.count }
        let sent = Array(characters[attemptStart...])
        // The error signal scraps everything sent before it in this attempt. When it's the burst
        // of dits at the end, wait until you pause (a word gap) so that every dit in the burst is
        // swallowed rather than the last few starting the next attempt; meanwhile the target
        // doesn't show the dits as mistakes.
        if let error = ErrorSignal.find(in: sent, target: target) {
            if error.atEnd {
                guard !keyDown, decoder.pending.isEmpty, let lastEnd = decoder.lastEnd,
                      Double(clock - lastEnd) / engine.sampleRate >= Decoder.wordGapUnits * timing.spacingUnit
                else { return }
            }
            startAttempt(at: attemptStart + error.restartAt)
            restarted = true
            stats.recordRestart()
            return
        }
        if sent.count > attemptSent.count {
            restarted = false
            // A new attempt clears the last result.
            if attemptSent.isEmpty && result != nil {
                result = nil
                resultText = ""
            }
            attemptSent = sent
        }
        // The attempt ends when you pause: after a word gap once you've sent enough characters
        // (so a stray extra letter at the end counts against this attempt rather than starting
        // the next), or after a long silence if you stopped short.
        guard !attemptSent.isEmpty, !keyDown, decoder.pending.isEmpty, let lastEnd = decoder.lastEnd else { return }
        let silence = Double(clock - lastEnd) / engine.sampleRate
        let enough = attemptSent.count >= target.count
        if silence >= (enough ? Decoder.wordGapUnits * timing.spacingUnit : attemptTimeout) {
            finishAttempt(attemptSent)
        }
    }

    private func finishAttempt(_ sent: [DecodedCharacter]) {
        let result = AttemptResult(target: target, sent: sent)
        self.result = result
        resultText = sent.enumerated().map { i, c in
            (i > 0 && (c.gapBefore ?? Decoder.longestMeasuredGap + 1) >= Decoder.wordGapUnits ? " " : "") + c.text
        }.joined()
        attemptStart += sent.count
        attemptSent = []
        stats.record(target: target, result: result, sent: sent, timing: timing, sampleRate: engine.sampleRate)
        if result.isCorrect {
            advanceAt = Date().addingTimeInterval(1.5)
        }
    }

    private func save() {
        defaults.set(frequency, forKey: "frequency")
        defaults.set(volume, forKey: "volume")
        defaults.set(wpm, forKey: "wpm")
        defaults.set(farnsworth, forKey: "farnsworth")
        defaults.set(effectiveWPM, forKey: "effectiveWPM")
        defaults.set(mode.rawValue, forKey: "mode")
        defaults.set(reversePaddles, forKey: "reversePaddles")
        defaults.set(autospace, forKey: "autospace")
        defaults.set(myCallsign, forKey: "myCallsign")
        defaults.set(practiceSource.rawValue, forKey: "practiceSource")
        defaults.set(sendingMode.rawValue, forKey: "sendingMode")
        pushSettings()
    }

    private func pushSettings() {
        var settings = OscillatorEngine.Settings()
        settings.frequency = frequency
        settings.volume = volume
        settings.keyer = Keyer.Settings(mode: mode, timing: timing, autospace: autospace)
        engine.update(settings)
    }
}

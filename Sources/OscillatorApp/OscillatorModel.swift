import AppKit
import Observation
import OscillatorAudio
import OscillatorCore

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
    var practiceText: String { didSet { defaults.set(practiceText, forKey: "practiceText") } }

    // MARK: Live state

    private(set) var ditPressed = false
    private(set) var dahPressed = false
    private(set) var keyDown = false
    private(set) var isPlaying = false
    private(set) var copiedText = ""
    private(set) var pendingCode = ""
    var audioError: String?

    var timing: MorseTiming {
        MorseTiming(characterWPM: wpm, effectiveWPM: farnsworth ? min(effectiveWPM, wpm) : nil)
    }

    private let defaults = UserDefaults.standard
    private let engine = OscillatorEngine()
    private let paddles = PaddleInput()
    private var decoder: Decoder
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        defaults.register(defaults: [
            "frequency": 600.0, "volume": 0.5, "wpm": 20.0, "farnsworth": false,
            "effectiveWPM": 10.0, "mode": KeyerMode.iambicB.rawValue, "reversePaddles": false,
            "autospace": false, "practiceText": "CQ CQ DE G3AJM G3AJM K",
        ])
        frequency = defaults.double(forKey: "frequency")
        volume = defaults.double(forKey: "volume")
        wpm = defaults.double(forKey: "wpm")
        farnsworth = defaults.bool(forKey: "farnsworth")
        effectiveWPM = defaults.double(forKey: "effectiveWPM")
        mode = KeyerMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .iambicB
        reversePaddles = defaults.bool(forKey: "reversePaddles")
        autospace = defaults.bool(forKey: "autospace")
        practiceText = defaults.string(forKey: "practiceText") ?? ""
        decoder = Decoder(sampleRate: 48_000, timing: MorseTiming(characterWPM: 20))
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

    func play() { engine.play(practiceText) }
    func stopPlaying() { engine.stopPlayback() }

    func clearCopy() {
        decoder.clear()
        copiedText = ""
        pendingCode = ""
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
            decoder = Decoder(sampleRate: engine.sampleRate, timing: timing)
        }
        decoder.timing = timing
        for mark in marks { decoder.add(mark) }
        decoder.update(now: status.clock, keyDown: status.keyDown)
        if keyDown != status.keyDown { keyDown = status.keyDown }
        if isPlaying != status.isPlaying { isPlaying = status.isPlaying }
        if copiedText != decoder.text { copiedText = decoder.text }
        if pendingCode != decoder.pending { pendingCode = decoder.pending }
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

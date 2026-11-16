import AVFoundation
import OscillatorCore
import os

/// The sidetone: runs the keyer and the tone generator inside the audio render callback, so
/// element timing is sample-accurate and the only delay is the output buffer.
///
/// The main thread sets the paddles and settings and collects finished marks through one small
/// lock that the render callback takes once per buffer.
public final class OscillatorEngine: @unchecked Sendable {
    public struct Settings: Equatable, Sendable {
        public var keyer = Keyer.Settings()
        public var frequency = 600.0
        public var volume = 0.5
        public init() {}
    }

    /// What the render callback reports back.
    public struct Status: Sendable {
        public var clock = 0
        public var keyDown = false
        public var isPlaying = false
    }

    private struct Shared {
        var dit = false
        var dah = false
        var settings = Settings()
        var marks: [Mark] = []
        var status = Status()
        var playbackRequest: [(Bool, Int)]?
        var stopPlayback = false
        var resetKeyer = false
    }

    /// State only the render thread touches.
    private final class RenderState {
        var keyer: Keyer
        var tone: ToneGenerator
        var playback: [(Bool, Int)] = []
        var playbackIndex = 0
        var playbackRemaining = 0

        init(sampleRate: Double, settings: Settings) {
            keyer = Keyer(sampleRate: sampleRate, settings: settings.keyer)
            tone = ToneGenerator(sampleRate: sampleRate, frequency: settings.frequency, volume: settings.volume)
        }
    }

    private let shared: OSAllocatedUnfairLock<Shared>
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var configObserver: NSObjectProtocol?
    public private(set) var sampleRate: Double = 48_000

    public init() {
        var initial = Shared()
        initial.marks.reserveCapacity(256)
        shared = OSAllocatedUnfairLock(initialState: initial)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // The output device or its sample rate changed: rebuild the graph.
            try? self?.start()
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        engine.stop()
    }

    // MARK: - Control (main thread)

    public func start() throws {
        engine.stop()
        if let source {
            engine.detach(source)
            self.source = nil
        }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [.mixWithOthers])
        try session.setPreferredIOBufferDuration(0.003)
        try session.setActive(true)
        #endif

        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = rate > 0 ? rate : 48_000
        let settings = shared.withLock { $0.settings }
        let render = RenderState(sampleRate: sampleRate, settings: settings)
        let shared = self.shared

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let frames = Int(frameCount)

            // One lock per buffer: read the paddles and settings, take any playback request.
            let input = shared.withLock { s -> (Bool, Bool, Settings, [(Bool, Int)]?, Bool, Bool) in
                let request = s.playbackRequest
                s.playbackRequest = nil
                let stop = s.stopPlayback, reset = s.resetKeyer
                s.stopPlayback = false
                s.resetKeyer = false
                return (s.dit, s.dah, s.settings, request, stop, reset)
            }
            let (dit, dah, settings, request, stop, reset) = input
            render.keyer.settings = settings.keyer
            render.tone.frequency = settings.frequency
            render.tone.volume = settings.volume
            if reset { render.keyer.reset() }
            if let request {
                render.playback = request
                render.playbackIndex = 0
                render.playbackRemaining = request.first?.1 ?? 0
            }
            // Touching the paddles (or Stop) cancels practice-text playback.
            if stop || dit || dah { render.playback = [] }

            var keyDown = false
            var newMarks: [Mark] = []
            for i in 0..<frames {
                let out = render.keyer.tick(dit: dit, dah: dah)
                keyDown = out.keyDown
                if let mark = out.mark { newMarks.append(mark) }
                if !keyDown, render.playbackIndex < render.playback.count {
                    keyDown = render.playback[render.playbackIndex].0
                    render.playbackRemaining -= 1
                    if render.playbackRemaining <= 0 {
                        render.playbackIndex += 1
                        if render.playbackIndex < render.playback.count {
                            render.playbackRemaining = render.playback[render.playbackIndex].1
                        } else {
                            render.playback = []
                        }
                    }
                }
                data[i] = render.tone.next(keyDown: keyDown)
            }
            for buffer in buffers.dropFirst() {
                if let other = buffer.mData { memcpy(other, data, frames * MemoryLayout<Float>.size) }
            }

            let status = Status(clock: render.keyer.clock, keyDown: keyDown,
                                isPlaying: render.playbackIndex < render.playback.count)
            let finished = newMarks
            shared.withLock { s in
                s.marks.append(contentsOf: finished)
                s.status = status
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        setLowLatency()
        engine.prepare()
        try engine.start()
    }

    public func stop() { engine.stop() }

    public func setPaddles(dit: Bool, dah: Bool) {
        shared.withLock {
            $0.dit = dit
            $0.dah = dah
        }
    }

    public func update(_ settings: Settings) {
        shared.withLock { $0.settings = settings }
    }

    /// Lets go of both paddles and clears the keyer (e.g. when the app loses focus mid-squeeze).
    public func releaseAll() {
        shared.withLock {
            $0.dit = false
            $0.dah = false
            $0.resetKeyer = true
        }
    }

    public func play(_ text: String) {
        let timing = shared.withLock { $0.settings.keyer.timing }
        let segments = TextKeying.segments(for: text, timing: timing, sampleRate: sampleRate)
        shared.withLock { $0.playbackRequest = segments }
    }

    public func stopPlayback() {
        shared.withLock {
            $0.playbackRequest = nil
            $0.stopPlayback = true
        }
    }

    /// Marks finished since the last call, and the latest status.
    public func poll() -> ([Mark], Status) {
        shared.withLock { s in
            let marks = s.marks
            s.marks.removeAll(keepingCapacity: true)
            return (marks, s.status)
        }
    }

    /// Asks the output device for a small buffer (128 frames, under 3 ms at 48 kHz).
    private func setLowLatency() {
        #if os(macOS)
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames: UInt32 = 128
        AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                             &frames, UInt32(MemoryLayout<UInt32>.size))
        #endif
    }
}

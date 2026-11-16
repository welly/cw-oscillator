import OscillatorCore
import SwiftUI

struct ContentView: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            KeyPanel()
                .padding()
            Form {
                Section("Sidetone") {
                    LabeledSlider(title: "Pitch", value: $model.frequency, range: 300...1200, step: 10) {
                        "\(Int($0)) Hz"
                    }
                    LabeledSlider(title: "Volume", value: $model.volume, range: 0...1, step: 0.01) {
                        "\(Int(($0 * 100).rounded())) %"
                    }
                }
                Section("Speed") {
                    LabeledSlider(title: "Character speed", value: $model.wpm, range: 5...60, step: 1) {
                        "\(Int($0)) WPM"
                    }
                    Toggle("Farnsworth spacing", isOn: $model.farnsworth)
                    if model.farnsworth {
                        LabeledSlider(title: "Effective speed", value: $model.effectiveWPM,
                                      range: 5...max(5, model.wpm), step: 1) {
                            "\(Int($0)) WPM"
                        }
                        .disabled(model.wpm <= 5)
                    }
                    LabeledContent("Dit / letter gap / word gap") {
                        Text("\(ms(model.timing.dit)) / \(ms(model.timing.letterGap)) / \(ms(model.timing.wordGap))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Keyer") {
                    Picker("Mode", selection: $model.mode) {
                        ForEach(KeyerMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Reverse paddles", isOn: $model.reversePaddles)
                    Toggle("Autospace", isOn: $model.autospace)
                        .help("After a pause, holds the next character back until a full letter gap has passed, so your spacing matches the Farnsworth setting.")
                        .disabled(model.mode == .straight)
                }
                Section {
                    CopyView()
                } header: {
                    HStack {
                        Text("Copy")
                        Spacer()
                        Button("Clear") { model.clearCopy() }
                            .buttonStyle(.borderless)
                    }
                }
                Section("Listen") {
                    HStack {
                        TextField("Text to play", text: $model.practiceText, prompt: Text("CQ CQ DE G3AJM <AR>"))
                            .onSubmit { model.play() }
                        if model.isPlaying {
                            Button("Stop") { model.stopPlaying() }
                        } else {
                            Button("Play") { model.play() }
                                .disabled(model.practiceText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    Text("Plays at the speed and spacing above. Type prosigns as <AR>, <SK>, <BT>, <KN>.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .alert("Audio", isPresented: Binding(get: { model.audioError != nil }, set: { if !$0 { model.audioError = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.audioError ?? "")
        }
    }

    private func ms(_ seconds: Double) -> String { "\(Int((seconds * 1000).rounded())) ms" }
}

/// The key lamp and the two paddle lights.
private struct KeyPanel: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                PaddleLight(label: "DIT", on: model.ditPressed)
                Circle()
                    .fill(model.keyDown ? Color.orange : Color.secondary.opacity(0.2))
                    .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 1))
                    .frame(width: 64, height: 64)
                    .shadow(color: model.keyDown ? .orange.opacity(0.7) : .clear, radius: 12)
                    .accessibilityLabel(model.keyDown ? "Key down" : "Key up")
                PaddleLight(label: "DAH", on: model.dahPressed)
            }
            Text("Paddle: Left/Right Control (VBand adapter), or the [ and ] keys")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PaddleLight: View {
    let label: String
    let on: Bool

    var body: some View {
        Text(label)
            .font(.system(.headline, design: .monospaced))
            .frame(width: 64, height: 32)
            .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: .rect(cornerRadius: 6))
            .foregroundStyle(on ? Color.white : Color.secondary)
    }
}

private struct CopyView: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(model.copiedText)
                    Text(model.pendingCode)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("end")
            }
            .frame(minHeight: 70, maxHeight: 140)
            .onChange(of: model.copiedText) { proxy.scrollTo("end", anchor: .bottom) }
            .overlay {
                if model.copiedText.isEmpty && model.pendingCode.isEmpty {
                    Text("Send with the paddle; what you send appears here.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(format(value))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }
}

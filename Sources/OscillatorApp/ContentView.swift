import OscillatorCore
import SwiftUI

struct ContentView: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                CopyView()
                GapReadout(gap: model.lastGap)
            } header: {
                HStack {
                    Text("Copy")
                    Spacer()
                    Button("Clear") { model.clearCopy() }
                        .buttonStyle(.borderless)
                }
            }
            Section {
                KeyPanel()
                    .padding(.vertical, 6)
            }
            Section("Sidetone") {
                LabeledSlider(title: "Pitch", value: $model.frequency, range: 300...1200, step: 10) {
                    "\(Int($0)) Hz"
                }
                LabeledSlider(title: "Volume", value: $model.volume, range: 0...1, step: 0.01) {
                    "\(Int(($0 * 100).rounded())) %"
                }
            }
            Section("Keyer") {
                LabeledSlider(title: "Speed", value: $model.wpm, range: 5...60, step: 1) {
                    "\(Int($0)) WPM"
                }
                Picker("Mode", selection: $model.mode) {
                    ForEach(KeyerMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Reverse paddles", isOn: $model.reversePaddles)
                Toggle("Autospace", isOn: $model.autospace)
                    .help("After a pause, holds the next character back until a full letter gap has passed, so your characters come out properly spaced.")
                    .disabled(model.mode == .straight)
            }
        }
        .formStyle(.grouped)
        .alert("Audio", isPresented: Binding(get: { model.audioError != nil }, set: { if !$0 { model.audioError = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.audioError ?? "")
        }
    }
}

/// The key lamp and the two paddle lights.
private struct KeyPanel: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
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

/// The last gap between two characters, in units, against the 3-unit letter gap and
/// 7-unit word gap.
private struct GapReadout: View {
    let gap: CharacterGap?

    var body: some View {
        LabeledContent("Last gap") {
            if let gap {
                HStack(spacing: 8) {
                    Text("\(gap.before) → \(gap.after)")
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "%.1f units", gap.units))
                        .monospacedDigit()
                    Text(label(gap.kind))
                        .foregroundStyle(colour(gap.kind))
                }
            } else {
                Text("letter gap 3 units, word gap 7")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func label(_ kind: CharacterGap.Kind) -> String {
        switch kind {
        case .letter: "letter gap"
        case .longLetter: "long letter gap"
        case .word: "word space"
        }
    }

    private func colour(_ kind: CharacterGap.Kind) -> Color {
        switch kind {
        case .letter: .green
        case .longLetter: .orange
        case .word: .secondary
        }
    }
}

private struct CopyView: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(model.copiedText)
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
                // No `step:` on the slider itself: macOS would draw a tick mark for every step.
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                Text(format(value))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }
}

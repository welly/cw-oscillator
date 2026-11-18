import OscillatorCore
import SwiftUI

/// Settings: the Settings window (⌘,) on the Mac, a sheet on iOS.
public struct SettingsView: View {
    @Environment(OscillatorModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var model = model
        Form {
            Section("Sidetone") {
                LabeledSlider(title: "Pitch", value: $model.frequency, range: 300...1200, step: 10) {
                    "\(Int($0)) Hz"
                }
                LabeledSlider(title: "Volume", value: $model.volume, range: 0...1, step: 0.01) {
                    "\(Int(($0 * 100).rounded())) %"
                }
            }
            Section("Keyer") {
                LabeledSlider(title: "Character speed", value: $model.wpm, range: 5...60, step: 1) {
                    "\(Int($0)) WPM"
                }
                Toggle(isOn: $model.farnsworth) {
                    Text("Farnsworth spacing")
                    Text("Characters at full speed with longer gaps between them, judged against the effective speed.")
                }
                if model.farnsworth {
                    LabeledSlider(title: "Effective speed", value: $model.effectiveWPM,
                                  range: 5...max(6, model.wpm), step: 1) {
                        "\(Int($0)) WPM"
                    }
                    .disabled(model.wpm <= 5)
                }
                Picker("Mode", selection: $model.mode) {
                    ForEach(KeyerMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Reverse paddles", isOn: $model.reversePaddles)
                #if os(macOS)
                Toggle(isOn: $model.backgroundKeying) {
                    Text("Keep working in the background")
                    Text("Hear the paddle while another app is in front. Reads the VBand adapter directly, so needs Input Monitoring.")
                }
                if model.backgroundAccessDenied {
                    HStack {
                        Label("Input Monitoring isn't allowed for CW Training Oscillator.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Privacy Settings…") { HIDPaddle.openPrivacySettings() }
                    }
                    .font(.callout)
                } else if model.backgroundKeying && !model.backgroundExclusive {
                    Text("macOS shares the adapter, so the paddle also presses Control in the app in front.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                #endif
                #if os(iOS)
                Toggle(isOn: $model.showTouchPaddles) {
                    Text("On-screen paddles")
                    Text("Dit and dah pads for sending without a paddle plugged in.")
                }
                #endif
                Toggle(isOn: $model.autospace) {
                    Text("Autospace")
                    Text("After a pause, holds your next character back until a full letter gap has passed.")
                }
                .disabled(model.mode == .straight)
            }
            Section("Practice") {
                TextField("Your callsign", text: $model.myCallsign)
                    .textCase(.uppercase)
                    .autocorrectionDisabled()
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        #endif
    }
}

struct LabeledSlider: View {
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


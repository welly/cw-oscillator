import OscillatorCore
import SwiftUI

/// The Settings window (⌘,).
struct SettingsView: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
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
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

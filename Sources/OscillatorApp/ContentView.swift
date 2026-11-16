import OscillatorCore
import SwiftUI

struct ContentView: View {
    @Environment(OscillatorModel.self) private var model
    @State private var showingHelp = false
    @Environment(\.openWindow) private var openWindow
    /// Height beyond the minimum, given to the copy box.
    @State private var extraHeight: CGFloat = 0

    /// The smallest size the layout fits; the window starts at this size.
    static let minimumSize = CGSize(width: 560, height: 500)

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Form {
                if model.sendingMode == .free {
                    Section {
                        CopyView(height: 196 + extraHeight, placeholder: "Send anything: you'll hear it and see it copied here.")
                    } header: {
                        copyHeader
                    }
                    timingSection
                } else {
                    practiceSections
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Divider()
            HStack(spacing: 14) {
                Stepper(value: $model.wpm, in: 5...60, step: 1) {
                    Text(model.speedLabel).monospacedDigit()
                }
                .help(model.farnsworth ? "Character speed (effective speed is in Settings)" : "Keyer speed")
                Text(model.mode.label)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    openWindow(id: "stats")
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .help("Statistics (⌘I)")
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    showingHelp.toggle()
                } label: {
                    Image(systemName: "questionmark")
                }
                .buttonBorderShape(.circle)
                .help("About letter and word gaps")
                .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                    HelpView()
                        .frame(width: 440, height: 480)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            extraHeight = max(0, height - Self.minimumSize.height)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Mode", selection: $model.sendingMode) {
                    ForEach(SendingMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("Free: just hear your key. Practice: send targets and see how you did.")
            }
        }
        .alert("Audio", isPresented: Binding(get: { model.audioError != nil }, set: { if !$0 { model.audioError = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.audioError ?? "")
        }
    }

    @ViewBuilder private var practiceSections: some View {
        @Bindable var model = model
        Section {
            PracticeView()
        } header: {
            HStack {
                Text("Send this")
                Spacer()
                Picker("Practise", selection: $model.practiceSource) {
                    ForEach(PracticeSource.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button {
                    model.restartAttempt()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .keyboardShortcut(.cancelAction)
                .help("Start this one again (Esc, or send the error signal: eight dits)")
                Button("Next") { model.nextTarget() }
                    .help("Skip to a new target")
            }
        }
        timingSection
        Section {
            CopyView(height: 54 + extraHeight, placeholder: "Everything you send is copied here.")
        } header: {
            copyHeader
        }
    }

    private var timingSection: some View {
        Section {
            TimingStripView()
                .frame(height: 74)
        } header: {
            HStack {
                Text("Timing")
                Spacer()
                // In free sending, show the paddles too: handy for checking the paddle is wired
                // the right way round. In practice the target and strip show your keying.
                if model.sendingMode == .free { KeyLights() }
            }
        }
    }

    private var copyHeader: some View {
        HStack {
            Text("Copy")
            Spacer()
            Button("Clear") { model.clearCopy() }
                .buttonStyle(.borderless)
        }
    }
}

/// The two paddle lights either side of the key lamp, small.
private struct KeyLights: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            PaddleLight(label: "DIT", on: model.ditPressed)
            Circle()
                .fill(model.keyDown ? Color.orange : Color.secondary.opacity(0.2))
                .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 1))
                .frame(width: 18, height: 18)
                .shadow(color: model.keyDown ? .orange.opacity(0.7) : .clear, radius: 6)
                .accessibilityLabel(model.keyDown ? "Key down" : "Key up")
            PaddleLight(label: "DAH", on: model.dahPressed)
        }
    }
}

private struct PaddleLight: View {
    let label: String
    let on: Bool

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .frame(width: 36, height: 18)
            .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: .rect(cornerRadius: 5))
            .foregroundStyle(on ? Color.white : Color.secondary)
    }
}

private struct CopyView: View {
    @Environment(OscillatorModel.self) private var model
    let height: CGFloat
    let placeholder: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(model.copiedText)
                    .font(.system(.title3, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("end")
            }
            .frame(height: height)
            .onChange(of: model.copiedText) { proxy.scrollTo("end", anchor: .bottom) }
            .overlay {
                if model.copiedText.isEmpty && model.pendingCode.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                }
            }
        }
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

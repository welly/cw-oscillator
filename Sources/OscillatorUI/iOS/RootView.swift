#if os(iOS)
import OscillatorCore
import SwiftUI
import UIKit

/// The iOS app's one screen: the same Free and Practice modes as the Mac, with the dit and dah
/// pads at the bottom for sending without a paddle plugged in.
public struct RootView: View {
    @Environment(OscillatorModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingStats = false
    @State private var showingHelp = false

    public init() {}

    public var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 12) {
                if model.sendingMode == .practice {
                    practiceCard
                    timingCard
                    copyCard(placeholder: "Everything you send is copied here.")
                } else {
                    copyCard(placeholder: "Send anything: you'll hear it and see it copied here.")
                    timingCard
                }
                speedRow
                if model.showTouchPaddles {
                    TouchPaddles()
                        .frame(height: sizeClass == .regular ? 200 : 150)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $model.sendingMode) {
                        ForEach(SendingMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingStats = true } label: { Image(systemName: "chart.bar.xaxis") }
                        .accessibilityLabel("Statistics")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingHelp = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("Help")
                    Button { model.showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $model.showingSettings) {
            SheetContainer(title: "Settings") { SettingsView() }
        }
        .sheet(isPresented: $showingStats) {
            SheetContainer(title: "Statistics") { StatisticsView() }
        }
        .sheet(isPresented: $showingHelp) {
            SheetContainer(title: "Help") { HelpView() }
        }
        .alert("Audio", isPresented: Binding(get: { model.audioError != nil }, set: { if !$0 { model.audioError = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.audioError ?? "")
        }
        .onAppear { model.start() }
    }

    private var practiceCard: some View {
        @Bindable var model = model
        return Card("Send this") {
                Menu {
                    Picker("Practise", selection: $model.practiceSource) {
                        ForEach(PracticeSource.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Text(model.practiceSource.label)
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                Button { model.restartAttempt() } label: { Image(systemName: "arrow.counterclockwise") }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Start again")
                Button("Next") { model.nextTarget() }
        } content: {
            PracticeView()
        }
    }

    private var timingCard: some View {
        Card("Timing") {
            if model.sendingMode == .free { KeyLamp() }
        } content: {
            TimingStripView(visibleUnits: sizeClass == .regular ? 72 : 44)
                .frame(height: 74)
        }
    }

    private func copyCard(placeholder: String) -> some View {
        Card("Copy") {
            Button("Clear") { model.clearCopy() }
        } content: {
            CopyText(placeholder: placeholder)
                .frame(minHeight: 44, maxHeight: .infinity)
        }
    }

    private var speedRow: some View {
        @Bindable var model = model
        return HStack {
            Stepper(value: $model.wpm, in: 5...60, step: 1) {
                HStack(spacing: 8) {
                    Text(model.speedLabel).monospacedDigit().fontWeight(.semibold)
                    Text(model.mode.label).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// A rounded panel with a small header, like a grouped list section.
private struct Card<Accessory: View, Content: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content

    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                accessory
                    .font(.subheadline)
            }
            .padding(.horizontal, 4)
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
    }
}

/// A sheet with a title and a Done button.
private struct SheetContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// The key lamp: lit while the sidetone sounds.
private struct KeyLamp: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        Circle()
            .fill(model.keyDown ? Color.orange : Color.secondary.opacity(0.2))
            .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 1))
            .frame(width: 14, height: 14)
            .shadow(color: model.keyDown ? .orange.opacity(0.7) : .clear, radius: 5)
            .accessibilityLabel(model.keyDown ? "Key down" : "Key up")
    }
}

private struct CopyText: View {
    @Environment(OscillatorModel.self) private var model
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
            .onChange(of: model.copiedText) { proxy.scrollTo("end", anchor: .bottom) }
            .overlay {
                if model.copiedText.isEmpty && model.pendingCode.isEmpty {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

/// Two pads, dit on the left and dah on the right (swapped with Reverse paddles). Touch both
/// to squeeze. Touches are tracked in UIKit so two fingers work independently and a finger
/// that slides onto the other pad moves across with it.
private struct TouchPaddles: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        // The model reverses the paddles, so the left pad lights for whichever it ends up as.
        let leftIsDit = !model.reversePaddles
        HStack(spacing: 12) {
            Pad(label: leftIsDit ? "DIT" : "DAH", lit: leftIsDit ? model.ditPressed : model.dahPressed)
            Pad(label: leftIsDit ? "DAH" : "DIT", lit: leftIsDit ? model.dahPressed : model.ditPressed)
        }
        .overlay {
            TouchSurface { left, right in model.setTouchPaddles(dit: left, dah: right) }
        }
        .accessibilityElement()
        .accessibilityLabel("Dit and dah pads")
    }
}

private struct Pad: View {
    let label: String
    let lit: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(lit ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .overlay {
                Text(label)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(lit ? Color.white : Color.secondary)
            }
            .shadow(color: .black.opacity(lit ? 0 : 0.06), radius: 2, y: 1)
    }
}

/// Reports whether any finger is on the left half and on the right half.
private struct TouchSurface: UIViewRepresentable {
    let onChange: (_ left: Bool, _ right: Bool) -> Void

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: SurfaceView, context: Context) {
        view.onChange = onChange
    }

    final class SurfaceView: UIView {
        var onChange: ((Bool, Bool) -> Void)?
        private var touches: Set<UITouch> = []
        private var state = (left: false, right: false)

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            self.touches.formUnion(touches)
            update()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update() }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            self.touches.subtract(touches)
            update()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            self.touches.subtract(touches)
            update()
        }

        private func update() {
            let mid = bounds.midX
            let xs = touches.map { $0.location(in: self).x }
            let new = (left: xs.contains { $0 < mid }, right: xs.contains { $0 >= mid })
            guard new != state else { return }
            state = new
            onChange?(new.left, new.right)
        }
    }
}
#endif

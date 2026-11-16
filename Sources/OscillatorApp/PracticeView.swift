import OscillatorCore
import SwiftUI

/// The target to send, marked up as you send it: each character green or red, and under each
/// gap a bar for how the spacing went.
struct PracticeView: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        if model.target.isEmpty {
            VStack(spacing: 8) {
                Text("Set your callsign to practise it.")
                SettingsLink { Text("Open Settings…") }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            practice
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 10) {
            TargetLine(target: model.target, characters: characterStatuses, gaps: gapStatuses,
                       gapUnits: gapUnits, next: model.result == nil ? model.attemptSent.count : nil)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: 44)
            summary
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 4)
    }

    // MARK: Statuses: the finished result, or a live position-by-position view while sending.

    private var characterStatuses: [AttemptResult.CharacterStatus?] {
        if let result = model.result { return result.characters }
        let sent = model.attemptSent
        return model.target.tokens.indices.map { k in
            guard k < sent.count else { return nil }
            return sent[k].text == model.target.tokens[k].text ? .correct : .wrong(sent[k].text)
        }
    }

    private var gapUnits: [Double?] {
        if let result = model.result { return result.gapUnits }
        let sent = model.attemptSent
        return model.target.tokens.indices.map { k in k > 0 && k < sent.count ? sent[k].gapBefore : nil }
    }

    private var gapStatuses: [AttemptResult.GapStatus?] {
        if let result = model.result { return result.gaps }
        return zip(model.target.tokens, gapUnits).map { token, units in
            units.map { AttemptResult.gapStatus(units: $0, startsWord: token.startsWord) }
        }
    }

    @ViewBuilder private var summary: some View {
        if let result = model.result {
            if result.isCorrect {
                HStack(spacing: 6) {
                    Label("Correct", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if result.longGaps > 0 {
                        Text("· \(plural(result.longGaps, "long letter gap"))")
                            .foregroundStyle(.orange)
                    }
                    if model.streak > 1 {
                        Text("· \(model.streak) in a row")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Text("Copied as")
                        .foregroundStyle(.secondary)
                    Text(model.resultText.isEmpty ? "nothing" : model.resultText)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                    Text("· " + problems(result))
                        .foregroundStyle(.red)
                    Text("· have another go")
                        .foregroundStyle(.secondary)
                }
            }
        } else if model.attemptSent.isEmpty && model.restarted {
            Label("Starting again", systemImage: "arrow.counterclockwise")
                .foregroundStyle(.secondary)
        } else if model.attemptSent.isEmpty {
            Text("Send when you're ready")
                .foregroundStyle(.secondary)
        } else {
            Text("\(model.attemptSent.count) of \(model.target.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func problems(_ result: AttemptResult) -> String {
        var parts: [String] = []
        if result.characterErrors > 0 { parts.append(plural(result.characterErrors, "character error")) }
        let unwanted = result.gaps.filter { $0 == .unwantedSpace }.count
        let missing = result.gaps.filter { $0 == .missingSpace }.count
        if unwanted > 0 { parts.append(plural(unwanted, "unwanted space")) }
        if missing > 0 { parts.append(plural(missing, "missing space")) }
        return parts.joined(separator: ", ")
    }

    private func plural(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }
}

private struct TargetLine: View {
    let target: PracticeTarget
    let characters: [AttemptResult.CharacterStatus?]
    let gaps: [AttemptResult.GapStatus?]
    let gapUnits: [Double?]
    /// The character to send next (underlined), while an attempt is under way.
    let next: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(target.tokens.enumerated()), id: \.offset) { k, token in
                if k > 0 {
                    GapMark(startsWord: token.startsWord, status: gaps[k], units: gapUnits[k])
                }
                VStack(spacing: 3) {
                    Text(token.text)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .foregroundStyle(colour(characters[k]))
                    Rectangle()
                        .fill(k == next ? Color.accentColor : .clear)
                        .frame(height: 2)
                }
                .help(help(characters[k]))
            }
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.15), value: characters)
    }

    private func colour(_ status: AttemptResult.CharacterStatus?) -> Color {
        switch status {
        case nil: .primary
        case .correct: .green
        case .wrong, .missing: .red
        }
    }

    private func help(_ status: AttemptResult.CharacterStatus?) -> String {
        switch status {
        case .wrong(let sent): "Copied as \(sent)"
        case .missing: "Not sent"
        default: ""
        }
    }
}

/// The space between two target characters, with a bar underneath once it's been sent:
/// green for the right kind of gap, orange for a long letter gap, red for an unwanted or
/// missing word space.
private struct GapMark: View {
    let startsWord: Bool
    let status: AttemptResult.GapStatus?
    let units: Double?

    var body: some View {
        VStack(spacing: 3) {
            Spacer(minLength: 0)
            Capsule()
                .fill(colour)
                .frame(height: 4)
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
        }
        .frame(width: startsWord ? 24 : 10)
        .help(units.map { String(format: "%.1f units", $0) } ?? "")
    }

    private var colour: Color {
        switch status {
        case nil: .clear
        case .good: .green.opacity(0.7)
        case .long: .orange
        case .unwantedSpace, .missingSpace: .red
        }
    }
}

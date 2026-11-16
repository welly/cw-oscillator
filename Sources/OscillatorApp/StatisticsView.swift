import Charts
import OscillatorCore
import SwiftUI

/// The Statistics window: how this session is going.
struct StatisticsView: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        let stats = model.stats
        Form {
            Section {
                HStack(spacing: 10) {
                    Tile(title: "Attempts", value: "\(stats.attempts)",
                         detail: stats.restarts > 0 ? "\(stats.restarts) restarted" : nil)
                    Tile(title: "Correct", value: percent(stats.accuracy),
                         detail: stats.attempts > 0 ? "\(stats.correct) of \(stats.attempts)" : nil)
                    Tile(title: "Best run", value: "\(stats.bestStreak)",
                         detail: stats.streak > 0 ? "\(stats.streak) now" : nil)
                    let speed = stats.recentEffectiveWPM(at: model.timing)
                    Tile(title: "Sending speed", value: speed.map { "\(Int($0.wpm.rounded()))" } ?? "–",
                         detail: speed.map { "WPM · last \($0.attempts) at \(model.speedLabel.replacingOccurrences(of: " WPM", with: ""))" })
                        .help("The speed your sending works out at once your gaps are counted, over your last few attempts at the current speed settings. The keyer times the characters, so your spacing is what makes the difference: aim for \(speedTarget) WPM.")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if stats.history.contains(where: { $0.averageLetterGap != nil }) {
                    GapChart(history: stats.history)
                        .frame(height: 150)
                } else {
                    Text("Your letter gaps will appear here once you've sent a few targets.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            } header: {
                Text("Letter gap per attempt")
            } footer: {
                Text("3 is a perfect letter gap; over 4 is long; 5 or more copies as a word space. Green dots were correct attempts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Spacing") {
                LabeledContent("Letter gaps") {
                    if let average = stats.averageLetterGap {
                        Text(String(format: "%.1f average", average)
                             + (stats.letterGapSpread.map { String(format: ", ±%.1f", $0) } ?? ""))
                    } else {
                        Text("–")
                    }
                }
                LabeledContent("Long letter gaps") { Text(count(stats.longLetterGaps, of: stats.letterGaps.count)) }
                LabeledContent("Unwanted spaces") { Text(count(stats.unwantedSpaces, of: stats.letterGaps.count)) }
                LabeledContent("Word gaps") {
                    Text(stats.averageWordGap.map { String(format: "%.1f average", $0) } ?? "–")
                }
                LabeledContent("Missing spaces") { Text(count(stats.missingSpaces, of: stats.wordGaps.count)) }
            }

            Section {
                LabeledContent("Sent correctly") {
                    Text(stats.characterAccuracy.map { "\(percent($0)) of \(stats.characters)" } ?? "–")
                }
                if stats.extraCharacters > 0 {
                    LabeledContent("Extra characters") { Text("\(stats.extraCharacters)") }
                }
                LabeledContent("Most missed") {
                    let missed = stats.mostMissed()
                    if missed.isEmpty {
                        Text("–")
                    } else {
                        HStack(spacing: 10) {
                            ForEach(missed, id: \.0) { character, times in
                                Text("\(character) ×\(times)")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
            } header: {
                Text("Characters")
            } footer: {
                HStack {
                    Text("Since the app opened.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { model.resetStats() }
                        .disabled(stats.attempts == 0 && stats.restarts == 0)
                        .help("Start the statistics afresh")
                }
            }
        }
        .formStyle(.grouped)
        .monospacedDigit()
    }

    /// What to aim for: the effective speed with Farnsworth, otherwise the keyer speed.
    private var speedTarget: Int { Int(model.timing.effectiveWPM) }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
    }

    private func count(_ n: Int, of total: Int) -> String {
        total == 0 ? "–" : "\(n) of \(total)"
    }
}

private struct Tile: View {
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title, design: .rounded).weight(.semibold))
            Text(detail ?? " ").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.secondary, in: .rect(cornerRadius: 8))
    }
}

/// Average letter gap for each attempt, against the 3-unit target and the 4 and 5 thresholds.
private struct GapChart: View {
    let history: [PracticeStats.Attempt]

    var body: some View {
        let points = history.enumerated().compactMap { i, attempt in
            attempt.averageLetterGap.map { (index: i + 1, gap: min($0, 8), correct: attempt.correct) }
        }
        Chart {
            RectangleMark(yStart: .value("Long", 4), yEnd: .value("Space", 5))
                .foregroundStyle(.orange.opacity(0.12))
            RectangleMark(yStart: .value("Space", 5), yEnd: .value("Top", 8))
                .foregroundStyle(.red.opacity(0.08))
            RuleMark(y: .value("Target", 3))
                .foregroundStyle(.green.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            ForEach(points, id: \.index) { point in
                LineMark(x: .value("Attempt", point.index), y: .value("Gap", point.gap))
                    .foregroundStyle(.secondary.opacity(0.5))
                PointMark(x: .value("Attempt", point.index), y: .value("Gap", point.gap))
                    .foregroundStyle(point.correct ? .green : .red)
            }
        }
        .chartYScale(domain: 0...8)
        .chartYAxis { AxisMarks(values: [0, 3, 5, 8]) }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
        .chartXScale(domain: 1...max(10, points.last?.index ?? 1))
    }
}

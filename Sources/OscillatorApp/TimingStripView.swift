import OscillatorCore
import SwiftUI

/// The last few seconds of sending, scrolling right to left with now at the right edge.
///
/// Marks are amber bars; each character's letter sits under its marks; each gap between
/// characters is a line coloured by how it'll copy (green letter gap, orange long letter gap,
/// grey word space) with its length in spacing units above. While the key is up after a
/// character, the growing gap is drawn live with ticks at 3 (a letter gap) and 7 (a word gap).
/// The time shown scales with the effective speed, so Farnsworth gaps fit.
struct TimingStripView: View {
    @Environment(OscillatorModel.self) private var model

    /// How many units of time the strip shows.
    private static let visibleUnits = 72.0

    var body: some View {
        let strip = model.strip
        // Read everything here so the view is observed and redraws as it changes.
        let clock = strip.clock
        let spacingSamples = max(1, strip.spacingSamples)
        let scaleSamples = max(1, strip.scaleSamples)
        let marks = strip.marks
        let characters = strip.characters
        let keyDownSince = strip.keyDownSince
        let lastEnd = strip.lastEnd
        let pending = strip.pending

        Canvas { context, size in
            let perUnit = size.width / Self.visibleUnits
            func x(_ sample: Int) -> CGFloat {
                size.width - CGFloat(Double(clock - sample) / scaleSamples) * perUnit
            }
            let markY: CGFloat = 30
            let markHeight: CGFloat = 12

            // Baseline.
            context.fill(Path(CGRect(x: 0, y: markY - 0.5, width: size.width, height: 1)),
                         with: .color(.secondary.opacity(0.25)))

            // Gaps between characters, with their length.
            for (i, character) in characters.enumerated() where i > 0 || character.gapBefore != nil {
                guard let units = character.gapBefore else { continue }
                let from = x(character.start - Int(units * spacingSamples))
                let to = x(character.start)
                guard to > 0 else { continue }
                drawGap(context, from: from, to: to, y: markY, units: units, live: false)
            }

            // Marks.
            for mark in marks {
                let rect = CGRect(x: x(mark.start), y: markY - markHeight / 2,
                                  width: max(2, x(mark.end) - x(mark.start)), height: markHeight)
                guard rect.maxX > 0 else { continue }
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(.orange))
            }
            if let keyDownSince {
                let rect = CGRect(x: x(keyDownSince), y: markY - markHeight / 2,
                                  width: max(2, size.width - x(keyDownSince)), height: markHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(.orange))
            }

            // Letters under their marks.
            for character in characters {
                let centre = (x(character.start) + x(character.end)) / 2
                guard centre > -10 else { continue }
                context.draw(Text(character.text).font(.system(.callout, design: .monospaced).weight(.semibold)),
                             at: CGPoint(x: centre, y: markY + 22))
            }

            // The gap growing now.
            if keyDownSince == nil, pending.isEmpty, let lastEnd {
                let units = Double(clock - lastEnd) / spacingSamples
                if units <= Decoder.longestMeasuredGap {
                    drawGap(context, from: x(lastEnd), to: size.width, y: markY, units: units, live: true)
                    for (tick, label) in [(3.0, "3"), (7.0, "7")] {
                        let tx = x(lastEnd + Int(tick * spacingSamples))
                        context.fill(Path(CGRect(x: tx - 0.5, y: markY + 6, width: 1, height: 8)),
                                     with: .color(.secondary.opacity(0.6)))
                        context.draw(Text(label).font(.caption2).foregroundStyle(.secondary),
                                     at: CGPoint(x: tx, y: markY + 20))
                    }
                }
            }
        }
        .accessibilityLabel("Timing of your last few seconds of sending")
    }

    private func drawGap(_ context: GraphicsContext, from: CGFloat, to: CGFloat, y: CGFloat,
                         units: Double, live: Bool) {
        let colour: Color = switch CharacterGap.Kind(units: units) {
        case .letter: .green
        case .longLetter: .orange
        case .word: .secondary
        }
        var line = Path()
        line.move(to: CGPoint(x: from + 2, y: y))
        line.addLine(to: CGPoint(x: to - 2, y: y))
        context.stroke(line, with: .color(colour),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: live ? [4, 3] : []))
        let label = String(format: "%.1f", units)
        context.draw(Text(label).font(.caption.monospacedDigit()).foregroundStyle(colour),
                     at: CGPoint(x: (from + to) / 2, y: y - 18))
    }
}

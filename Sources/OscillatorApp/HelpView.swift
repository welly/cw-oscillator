import OscillatorCore
import SwiftUI

/// Explains units, letter gaps and word gaps, and how the app judges them. Shown from the ?
/// button and Help ▸ CW Training Oscillator Help.
struct HelpView: View {
    @Environment(OscillatorModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topic("Units") {
                    Text("All Morse timing is measured in **units**. One unit is the length of a dit. At \(Int(model.wpm)) WPM a unit is **\(ms(model.timing.unit))**.")
                }
                topic("The three gaps") {
                    GapRow(units: 1, name: "Between the dits and dahs of a character", detail: "The keyer does this for you.")
                    GapRow(units: 3, name: "Letter gap, between characters in a word", detail: model.timing.isFarnsworth
                           ? "\(ms(model.timing.letterGap)) at \(model.speedLabel)."
                           : "\(ms(model.timing.letterGap)) at \(model.speedLabel): the length of a dah.")
                    GapRow(units: 7, name: "Word gap, between words", detail: "\(ms(model.timing.wordGap)) at \(model.speedLabel).")
                }
                topic("Farnsworth spacing") {
                    Text("With Farnsworth spacing on (in Settings), characters are still sent at the character speed, but the gaps between them are stretched so the overall rate is the slower effective speed. You learn each character as a sound at full speed while having time to think between them.")
                    if model.timing.isFarnsworth {
                        Text("At \(model.speedLabel), a dit is \(ms(model.timing.unit)) but a spacing unit is **\(ms(model.timing.spacingUnit))**. Letter and word gaps are measured in spacing units, so 3 is still a perfect letter gap and 7 a word gap.")
                    } else {
                        Text("It's off at the moment, so a spacing unit is the same as a dit.")
                            .foregroundStyle(.secondary)
                    }
                    Text("A good way to progress: start with a low effective speed, get your sending consistently green, then raise the effective speed until it matches the character speed.")
                }
                topic("How your sending is copied") {
                    Text("A gap is judged by its length:")
                    VStack(alignment: .leading, spacing: 6) {
                        Swatch(colour: .green, text: "Under 4: a letter gap. 3 is perfect.")
                        Swatch(colour: .orange, text: "4 to 5: a long letter gap. Still copies as one word, but it's drifting.")
                        Swatch(colour: .secondary, text: "5 or more: a word space. A listener hears a new word.")
                    }
                    Text("These are spacing units (the same as dits without Farnsworth). A gap of under 2 dits doesn't end a character at all, so the next element joins it. A pause of over 10 spacing units is a break rather than spacing, and isn't measured.")
                        .foregroundStyle(.secondary)
                }
                topic("Timing strip") {
                    Text("Your last few seconds of sending, moving right to left. Amber bars are your dits and dahs, with the letter they made underneath. Each gap between characters is coloured as above, with its length in spacing units above it.")
                    Text("While you pause, the gap grows live as a dashed line, with ticks at 3 (letter gap) and 7 (word gap) to aim for.")
                }
                topic("Free and Practice") {
                    Text("The switch at the top of the window. Free is a plain practice oscillator: send anything, hear it, and see it copied with the timing strip. Practice gives you targets to send and judges them.")
                }
                topic("Send this") {
                    Text("Send the target with the paddle. Characters turn green or red as you go, and the bar under each gap shows how the spacing went: green right, orange long, red an unwanted space inside a word or a missing one between words.")
                    Text("An attempt ends when you pause for a word gap after sending it, so a stray extra character at the end counts as a mistake in that attempt rather than starting the next one. If you stop short, it ends after a longer pause.")
                    Text("Fumbled it? Send the error signal (eight dits) or press Esc, and the attempt starts again. Six or more dits will do. It still works if you go straight into them from the character you fumbled, or if they break up into letters like S S I or H I E, as long as you don't pause for a word gap. A run of dits that the target actually asks for, like HIS or SHE, isn't treated as an error.")
                    Text("Get it right (long letter gaps are allowed) and a new one appears. Otherwise send it again. Choose your callsign, random callsigns, words or QSO phrases from the menu; Next skips.")
                }
                topic("Statistics") {
                    Text("The chart button (⌘I) shows how the session is going: how many attempts were right, your average letter and word gaps and how consistent they are, the characters you miss most, and your speed.")
                    Text("Sending speed is what your sending works out at once your spacing is counted, averaged over your last five attempts at the current speed settings (change speed and it starts afresh). The keyer times the characters, so it's your gaps that bring it below the keyer speed. Aim for the keyer speed, or the effective speed if you use Farnsworth.")
                }
                topic("Tips") {
                    Text("Without Farnsworth, think of a letter gap as one silent dah, and a word gap as just over two. Common trouble spots are switching between letters and figures (G3) and the same paddle ending one character and starting the next (S then E).")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ms(_ seconds: Double) -> String { "\(Int((seconds * 1000).rounded())) ms" }

    private func topic(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GapRow: View {
    let units: Int
    let name: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(units)")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Swatch: View {
    let colour: Color
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Capsule().fill(colour).frame(width: 18, height: 4)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text)
        }
    }
}

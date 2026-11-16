import Foundation

public enum Element: Sendable, Equatable {
    case dit, dah

    public var opposite: Element { self == .dit ? .dah : .dit }
    public var symbol: Character { self == .dit ? "." : "-" }
}

/// The Morse table: letters, digits, punctuation and the common prosigns.
public enum MorseCode {
    /// Prosigns, shown with an overline (A̅R̅).
    public static let prosigns: [String: String] = [
        "AR": ".-.-.", "SK": "...-.-", "BT": "-...-", "KN": "-.--.", "AS": ".-...", "BK": "-...-.-",
    ]

    public static let characters: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.",
        "H": "....", "I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.",
        "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-", "U": "..-",
        "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--", "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "/": "-..-.", "'": ".----.",
        "!": "-.-.--", ":": "---...", ";": "-.-.-.", "-": "-....-", "\"": ".-..-.",
        "@": ".--.-.", "(": "-.--.-", ")": "-.--.-", "_": "..--.-", "$": "...-..-",
        "&": ".-...",
    ]

    /// Code → text for the decoder. Prosigns win where they share a pattern with punctuation
    /// (`-...-` reads as B̅T̅, not `=`).
    public static let decodeTable: [String: String] = {
        var table: [String: String] = [:]
        for (char, code) in characters where table[code] == nil { table[code] = String(char) }
        table["-.--.-"] = "("
        for (name, code) in prosigns { table[code] = overlined(name) }
        return table
    }()

    /// "AR" → "A̅R̅".
    public static func overlined(_ text: String) -> String {
        text.map { "\($0)\u{0305}" }.joined()
    }

    /// What the error signal (six or more dits, usually eight) copies as.
    public static let errorSignal = "⌫"

    /// True for the error signal: six or more dits at the end of a character. That includes
    /// dits sent straight on from a fumbled character without a letter gap (`--.` then eight
    /// dits reads as one long character). No real character ends in more than five dits.
    public static func isErrorSignal(_ code: String) -> Bool {
        trailingDits(code) >= 6
    }

    /// How many dits a code ends with: 3 for `-...`.
    public static func trailingDits(_ code: String) -> Int {
        code.reversed().prefix { $0 == "." }.count
    }

    /// The text for a code (the error signal included), or nil when it isn't in the table.
    public static func decode(_ code: String) -> String? {
        isErrorSignal(code) ? errorSignal : decodeTable[code]
    }
}

import Foundation

/// Something for the operator to send: characters (letters, figures, prosigns), split into words.
public struct PracticeTarget: Equatable, Sendable {
    public struct Token: Equatable, Sendable {
        /// As the decoder shows it: "G", "3", or "A̅R̅" for a prosign.
        public var text: String
        /// True when a word space comes before this character.
        public var startsWord: Bool
    }

    public var tokens: [Token]

    /// Parses text like "CQ DE G3AJM <AR>". Characters with no Morse code are dropped.
    public init(_ text: String) {
        var tokens: [Token] = []
        var newWord = false
        let chars = Array(text.uppercased())
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                newWord = !tokens.isEmpty
                i += 1
                continue
            }
            var token: String?
            if c == "<", let close = chars[(i + 1)...].firstIndex(of: ">"),
               MorseCode.prosigns[String(chars[(i + 1)..<close])] != nil {
                token = MorseCode.overlined(String(chars[(i + 1)..<close]))
                i = close + 1
            } else {
                if MorseCode.characters[c] != nil { token = String(c) }
                i += 1
            }
            if let token {
                tokens.append(Token(text: token, startsWord: newWord))
                newWord = false
            }
        }
        self.tokens = tokens
    }

    public var isEmpty: Bool { tokens.isEmpty }
    public var count: Int { tokens.count }

    /// The target as it should copy, e.g. "CQ DE G3AJM".
    public var text: String {
        tokens.map { ($0.startsWord ? " " : "") + $0.text }.joined()
    }
}

/// How an attempt at a target went, character by character and gap by gap.
public struct AttemptResult: Equatable, Sendable {
    public enum CharacterStatus: Equatable, Sendable {
        case correct
        /// Sent as something else (what was copied).
        case wrong(String)
        case missing
    }

    public enum GapStatus: Equatable, Sendable {
        /// The right kind of gap.
        case good
        /// A letter gap of 4 to 5 units: copies correctly but is drifting towards a word space.
        case long
        /// A letter gap of 5 units or more: copies as a word space.
        case unwantedSpace
        /// A word gap under 5 units: the words run together.
        case missingSpace
    }

    /// One per target character.
    public var characters: [CharacterStatus]
    /// One per target character: the gap before it (nil for the first, or when it can't be
    /// judged because a neighbour was missing or extra characters came between).
    public var gaps: [GapStatus?]
    /// The gap lengths in units, alongside `gaps`.
    public var gapUnits: [Double?]
    /// Characters copied that aren't in the target.
    public var extra: [String]

    public var characterErrors: Int {
        characters.filter { $0 != .correct }.count + extra.count
    }
    public var spacingErrors: Int {
        gaps.filter { $0 == .unwantedSpace || $0 == .missingSpace }.count
    }
    public var longGaps: Int { gaps.filter { $0 == .long }.count }
    /// Every character right and no unwanted or missing spaces (long letter gaps are allowed).
    public var isCorrect: Bool { characterErrors == 0 && spacingErrors == 0 }

    /// Judges one gap: `startsWord` says whether the target has a word space there.
    public static func gapStatus(units: Double, startsWord: Bool) -> GapStatus {
        let kind = CharacterGap.Kind(units: units)
        if startsWord { return kind == .word ? .good : .missingSpace }
        return kind == .letter ? .good : kind == .longLetter ? .long : .unwantedSpace
    }

    /// Lines what was sent up against the target (edit-distance alignment, so one missed or
    /// extra character doesn't throw everything after it out) and judges each gap.
    public init(target: PracticeTarget, sent: [DecodedCharacter]) {
        let t = target.tokens.map(\.text)
        let s = sent.map(\.text)
        let n = t.count, m = s.count

        // Edit distance table.
        var d = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = i }
        for j in 0...m { d[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let cost = t[i - 1] == s[j - 1] ? 0 : 1
                    d[i][j] = min(d[i - 1][j - 1] + cost, d[i - 1][j] + 1, d[i][j - 1] + 1)
                }
            }
        }

        // Walk back: which sent character (if any) each target character lines up with.
        var matched = [Int?](repeating: nil, count: n)
        var extra: [String] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && d[i][j] == d[i - 1][j - 1] + (t[i - 1] == s[j - 1] ? 0 : 1) {
                matched[i - 1] = j - 1
                i -= 1; j -= 1
            } else if i > 0 && d[i][j] == d[i - 1][j] + 1 {
                i -= 1
            } else {
                extra.insert(s[j - 1], at: 0)
                j -= 1
            }
        }

        characters = (0..<n).map { k in
            guard let j = matched[k] else { return .missing }
            return s[j] == t[k] ? .correct : .wrong(s[j])
        }
        var gaps: [GapStatus?] = []
        var gapUnits: [Double?] = []
        for k in 0..<n {
            guard k > 0, let j = matched[k], let previous = matched[k - 1], j == previous + 1,
                  let units = sent[j].gapBefore ?? (sent[j].start > sent[previous].end ? Decoder.longestMeasuredGap + 1 : nil)
            else {
                gaps.append(nil)
                gapUnits.append(nil)
                continue
            }
            gapUnits.append(units)
            gaps.append(Self.gapStatus(units: units, startsWord: target.tokens[k].startsWord))
        }
        self.gaps = gaps
        self.gapUnits = gapUnits
        self.extra = extra
    }
}

/// Where practice targets come from.
public enum PracticeSource: String, CaseIterable, Identifiable, Sendable {
    case myCallsign, callsigns, words, exchanges

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .myCallsign: "My callsign"
        case .callsigns: "Callsigns"
        case .words: "Words"
        case .exchanges: "QSO phrases"
        }
    }
}

/// Makes practice targets.
public struct PracticeGenerator {
    /// The operator's own callsign, used by `.myCallsign` and in QSO phrases.
    public var myCallsign: String

    public init(myCallsign: String) {
        self.myCallsign = myCallsign
    }

    public func next<R: RandomNumberGenerator>(_ source: PracticeSource, avoiding previous: String? = nil,
                                               using rng: inout R) -> PracticeTarget {
        for _ in 0..<5 {
            let target = PracticeTarget(make(source, using: &rng))
            if target.text != previous || source == .myCallsign { return target }
        }
        return PracticeTarget(make(source, using: &rng))
    }

    public func next(_ source: PracticeSource, avoiding previous: String? = nil) -> PracticeTarget {
        var rng = SystemRandomNumberGenerator()
        return next(source, avoiding: previous, using: &rng)
    }

    /// The callsign, or nothing when it isn't set (the app then asks for one). QSO phrases
    /// fall back to a placeholder.
    private var call: String { myCallsign.trimmingCharacters(in: .whitespaces).uppercased() }
    private var callForPhrases: String { call.isEmpty ? "M0ABC" : call }

    private func make<R: RandomNumberGenerator>(_ source: PracticeSource, using rng: inout R) -> String {
        switch source {
        case .myCallsign:
            return call
        case .callsigns:
            return Self.randomCallsign(using: &rng)
        case .words:
            return Self.words.randomElement(using: &rng)!
        case .exchanges:
            let phrase = Self.exchanges.randomElement(using: &rng)!
            return phrase
                .replacingOccurrences(of: "{CALL}", with: callForPhrases)
                .replacingOccurrences(of: "{OTHER}", with: Self.randomCallsign(using: &rng))
                .replacingOccurrences(of: "{RST}", with: ["599", "579", "559", "449", "5NN"].randomElement(using: &rng)!)
        }
    }

    /// A plausible callsign: prefix, figure, then one to three letters, sometimes /P.
    public static func randomCallsign<R: RandomNumberGenerator>(using rng: inout R) -> String {
        let prefixes = ["G", "G", "G", "M", "M", "2E", "GM", "GW", "GI", "EI", "F", "DL", "DK", "ON", "PA",
                        "EA", "I", "OH", "SM", "LA", "OZ", "SP", "OK", "HA", "S5", "9A", "K", "W", "N",
                        "AA", "VE", "VK", "ZL", "JA", "ZS"]
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let prefix = prefixes.randomElement(using: &rng)!
        let figure = Int.random(in: 0...9, using: &rng)
        let length = [1, 2, 2, 3, 3, 3, 3].randomElement(using: &rng)!
        let suffix = String((0..<length).map { _ in letters.randomElement(using: &rng)! })
        let portable = Int.random(in: 0..<10, using: &rng) == 0 ? "/P" : ""
        return "\(prefix)\(figure)\(suffix)\(portable)"
    }

    public static let words = [
        "THE", "AND", "NAME", "RIG", "ANT", "POWER", "HERE", "THERE", "GOOD", "VERY", "NICE", "SIGNAL",
        "STRONG", "WEAK", "FADING", "NOISE", "BAND", "OPEN", "CONDX", "QSB", "QRM", "QRN", "WEATHER",
        "SUNNY", "RAIN", "CLOUDY", "COLD", "WARM", "WIND", "TODAY", "MORNING", "EVENING", "NIGHT",
        "CALL", "THANKS", "AGAIN", "HOPE", "MEET", "SOON", "BEST", "WISHES", "ABOUT", "WORK", "HOME",
        "RADIO", "KEY", "PADDLE", "SPEED", "TONE", "COPY", "SOLID", "LOUD", "CLEAR", "DIPOLE", "VERTICAL",
        "BEAM", "WIRE", "TOWER", "METRES", "WATTS", "QRP", "CONTEST", "LOG", "CARD", "QSL", "BUREAU",
        "DIRECT", "SUMMIT", "PORTABLE", "FIELD", "CLUB", "MEMBER", "LICENCE", "YEARS", "FIRST", "TIME",
        "LONDON", "MANCHESTER", "EDINBURGH", "CARDIFF", "BELFAST", "DUBLIN", "PARIS", "BERLIN",
        "QUICK", "BROWN", "FOX", "JUMPS", "OVER", "LAZY", "DOG", "MORSE", "CODE", "PRACTICE", "SEND",
        "RECEIVE", "LISTEN", "RHYTHM", "SPACING", "LETTER", "WORD", "NUMBER", "MINUTE", "HOUR",
    ]

    /// Typical ragchew and contest phrases. {CALL} is the operator, {OTHER} a random station.
    public static let exchanges = [
        "CQ CQ DE {CALL} {CALL} K",
        "CQ TEST {CALL}",
        "{OTHER} DE {CALL} K",
        "{OTHER} DE {CALL} <KN>",
        "GM OM TNX FER CALL",
        "GA ES TNX FER CALL",
        "UR RST {RST} {RST}",
        "UR {RST} {RST} BK",
        "NAME AL AL",
        "QTH LONDON LONDON",
        "RIG IC7300 PWR 100W",
        "ANT DIPOLE UP 10M",
        "WX SUNNY TEMP 15C",
        "HW CPY? <BK>",
        "TNX FER QSO 73 <SK>",
        "73 ES GUD DX",
        "QRZ? DE {CALL}",
        "R R TU {RST} 001",
        "5NN 14",
        "<BT> HR SIG RPT IS {RST} <BT>",
    ]
}

/// Spots the error signal in an attempt, including the way beginners often send it: eight dits
/// that break up into I, S, H or E.
public enum ErrorSignal {
    /// Dits needed, whether as one character or a run of dit-only characters.
    public static let minimumDits = 6

    public struct Found: Equatable, Sendable {
        /// Index in `sent` just after the error signal: where the attempt starts again.
        public var restartAt: Int
        /// True when the error signal is the burst of dits at the very end of what was sent.
        /// It may not be over yet (more dits can follow), so wait for a pause before restarting
        /// rather than counting the rest of the burst as a new attempt.
        public var atEnd: Bool
    }

    /// Finds the error signal in an attempt, or nil.
    ///
    /// The error signal is a burst of six or more dits sent without a word gap: one character
    /// ending in six or more dits (perhaps run straight on from a fumbled character), and/or
    /// dit-only characters (E I S H 5) that the dits broke up into. A burst of dit-only
    /// characters that is exactly what the target asks for at that point (HIS, SHE) isn't one.
    public static func find(in sent: [DecodedCharacter], target: PracticeTarget) -> Found? {
        if let last = sent.indices.last {
            // Walk back over the burst of dits at the end.
            var start = last
            var dits = 0
            var i = last
            while i >= 0 {
                let character = sent[i]
                if let n = ditCount(character.text) {
                    dits += n
                    start = i
                } else {
                    // A fumbled character (*) or error signal (⌫) the dits ran on from: count
                    // its trailing dits, and the burst starts there.
                    if character.text == "*" || character.text == MorseCode.errorSignal {
                        dits += MorseCode.trailingDits(character.code)
                        start = i
                    }
                    break
                }
                // Stop at a word gap: the burst must be continuous.
                if i == 0 || (character.gapBefore ?? .infinity) >= Decoder.wordGapUnits { break }
                i -= 1
            }
            if dits >= minimumDits {
                let run = sent[start...].map(\.text)
                let expected = target.tokens.dropFirst(start).prefix(run.count)
                let isTarget = expected.map(\.text).elementsEqual(run)
                    && !expected.dropFirst().contains(where: \.startsWord)
                if !isTarget { return Found(restartAt: last + 1, atEnd: true) }
            }
        }
        // An error signal earlier on, followed by a fresh start without a pause.
        if let single = sent.lastIndex(where: { $0.text == MorseCode.errorSignal }) {
            return Found(restartAt: single + 1, atEnd: false)
        }
        return nil
    }

    /// The number of dits in a character made only of dits (E 1, I 2, S 3, H 4, 5 5), else nil.
    static func ditCount(_ text: String) -> Int? {
        guard text.count == 1, let code = MorseCode.characters[Character(text)],
              code.allSatisfy({ $0 == "." }) else { return nil }
        return code.count
    }
}

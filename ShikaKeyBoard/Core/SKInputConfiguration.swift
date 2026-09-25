import Foundation

/// Scheme rules shared by the input session and engine, with no UI dependencies.
struct SKInputConfiguration {
    let schemaID: String
    let inputPolicy: SKInputPolicy
    let spelling: SKSpellingProfile
    var language: SKConversionLanguage = .chinese
}

enum SKConversionLanguage { case chinese, japanese, mixed }

enum SKInputPolicy {
    case chineseRomanization
    case japaneseRomanization
    case mixedRomanization

    enum Action {
        case engineKey(Int32, insertIfUnhandled: Bool)
        case literal
    }

    /// Newline, uppercase letters and symbols retain the existing MVP behavior.
    func action(for text: String, isComposing: Bool) -> Action {
        switch self {
        case .chineseRomanization, .japaneseRomanization, .mixedRomanization:
            if text == " " && isComposing { return .engineKey(0x20, insertIfUnhandled: false) }
            if self == .japaneseRomanization && (text == "ー" || text == "-") {
                return .engineKey(45, insertIfUnhandled: false)
            }
            guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first,
                  (97...122).contains(scalar.value) || scalar.value == 39 else { return .literal }
            return .engineKey(Int32(scalar.value), insertIfUnhandled: true)
        }
    }
}

enum SKSpellingProfile {
    case fullPinyin
    case doublePinyin

    var syllableResource: String? {
        self == .doublePinyin ? "correction-syllables.json" : nil
    }

    func allowsCorrection(preedit: String) -> Bool {
        // Both current schemes use Chinese romanization. A non-ASCII prefix
        // represents a deliberate partial selection and must remain untouched.
        !preedit.unicodeScalars.contains { $0.value > 127 }
    }

    func isExact(comment: String, input: String, syllables: [String: String]) -> Bool {
        let parts = comment.split(whereSeparator: { $0 == " " || $0 == "'" })
        guard !parts.isEmpty else { return false }
        let code: String
        switch self {
        case .doublePinyin:
            let mapped = parts.compactMap { syllables[String($0)] }
            guard mapped.count == parts.count else { return false }
            code = mapped.joined()
        case .fullPinyin:
            code = normalize(parts.joined())
        }
        return code == normalize(input.replacingOccurrences(of: "'", with: ""))
    }

    private func normalize(_ code: String) -> String {
        switch self {
        case .fullPinyin:
            return code.replacingOccurrences(of: "nue", with: "nve")
                .replacingOccurrences(of: "lue", with: "lve")
        case .doublePinyin: return code
        }
    }
}

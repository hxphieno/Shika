import Foundation

enum SKChineseJapaneseScheme {
    static let configuration = SKInputConfiguration(schemaID: "shika_pinyin",
        inputPolicy: .chineseRomanization, spelling: .fullPinyin)

    static func configuration(for mode: SKChineseJapaneseMode) -> SKInputConfiguration {
        switch mode {
        case .chinese: return configuration
        case .japanese:
            return SKInputConfiguration(schemaID: "mozc_japanese", inputPolicy: .japaneseRomanization,
                spelling: .fullPinyin, language: .japanese)
        case .mixed:
            return SKInputConfiguration(schemaID: "shika_pinyin", inputPolicy: .mixedRomanization,
                spelling: .fullPinyin, language: .mixed)
        }
    }
}

enum SKChineseJapaneseMode: String {
    static let preferenceKey = "shika.chineseJapaneseMode"

    case chinese
    case japanese
    case mixed

    var next: SKChineseJapaneseMode {
        switch self {
        case .chinese: return .japanese
        case .japanese: return .mixed
        case .mixed: return .chinese
        }
    }
}

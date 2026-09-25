import Foundation

enum SKChineseJapaneseScheme {
    // Chinese conversion is the baseline for all three modes in this milestone.
    // Japanese conversion can be added here without changing Rime infrastructure.
    static let configuration = SKInputConfiguration(schemaID: "shika_pinyin",
        inputPolicy: .chineseRomanization, spelling: .fullPinyin)
}

enum SKChineseJapaneseMode {
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

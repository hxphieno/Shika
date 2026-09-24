import Foundation

enum SKInputScheme: String {
    case chineseJapanese
    case shuangpin

    static let preferenceKey = "keyboard.inputScheme"

    var schemaID: String {
        switch self {
        case .chineseJapanese: return SKChineseJapaneseScheme.chineseSchemaID
        case .shuangpin: return SKShuangpinScheme.schemaID
        }
    }

    var next: SKInputScheme {
        self == .chineseJapanese ? .shuangpin : .chineseJapanese
    }
}

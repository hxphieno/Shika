import Foundation

enum SKInputScheme: String, CaseIterable {
    case chineseJapanese
    case shuangpin

    static let preferenceKey = "keyboard.inputScheme"

    var configuration: SKInputConfiguration {
        switch self {
        case .chineseJapanese: return SKChineseJapaneseScheme.configuration
        case .shuangpin: return SKShuangpinScheme.configuration
        }
    }

    init?(schemaID: String) {
        guard let scheme = Self.allCases.first(where: { $0.configuration.schemaID == schemaID }) else { return nil }
        self = scheme
    }

    var next: SKInputScheme {
        self == .chineseJapanese ? .shuangpin : .chineseJapanese
    }
}

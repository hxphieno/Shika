import Foundation

enum SKInputScheme: String {
    case chineseJapanese
    case shuangpin

    static let preferenceKey = "keyboard.inputScheme"

    var next: SKInputScheme {
        self == .chineseJapanese ? .shuangpin : .chineseJapanese
    }
}

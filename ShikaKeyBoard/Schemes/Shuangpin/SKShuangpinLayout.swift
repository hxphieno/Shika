import Foundation

/// Xiaohe (小鹤) phonetic layout, not the separate 音形 auxiliary-code scheme.
/// References: https://flypy.cc/ and
/// https://github.com/rime/rime-double-pinyin/blob/master/double_pinyin_flypy.schema.yaml
enum SKShuangpinLayout {
    static let rows = [Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm")]
    static let initials: [Character: String] = ["u": "sh", "i": "ch", "v": "zh"]
    static let finals: [Character: String] = [
        "q": "iu", "w": "ei", "e": "e", "r": "uan", "t": "üe", "y": "un",
        "u": "u", "i": "i", "o": "o / uo", "p": "ie",
        "a": "a", "s": "ong / iong", "d": "ai", "f": "en", "g": "eng",
        "h": "ang", "j": "an", "k": "ing / uai", "l": "iang / uang",
        "z": "ou", "x": "ia / ua", "c": "ao", "v": "ui / ü", "b": "in",
        "n": "iao", "m": "ian"
    ]
}

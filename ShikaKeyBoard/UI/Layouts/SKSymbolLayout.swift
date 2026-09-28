import Foundation

struct SKSymbolLayout {
    // Columns are read top to bottom, then swiped horizontally. Keep common
    // writing marks first; opening/closing marks are separate keys so the
    // user can place text between them without moving the cursor backwards.
    static let columns: [[String]] = [
        ["，", "。", "？", "！"],
        ["、", "；", "：", "……"],
        ["（", "）", "“", "”"],
        ["《", "》", "【", "】"],
        ["「", "」", "『", "』"],
        [".", ",", "?", "!"],
        ["@", "_", "-", "/"],
        [":", ";", "'", "\""],
        ["(", ")", "[", "]"],
        ["{", "}", "<", ">"],
        ["+", "−", "×", "÷"],
        ["=", "%", "‰", "°"],
        ["¥", "$", "€", "£"],
        ["#", "&", "*", "\\"],
        ["~", "|", "·", "——"],
        // iOS punctuation variants, kept after the existing familiar inventory.
        ["‘", "’", "〔", "〕"],
        ["〈", "〉", "［", "］"],
        ["｛", "｝", "＜", "＞"],
        ["«", "»", "„", "＂"],
        ["＇", "…", "⋯", "⋯⋯"],
        ["–", "—", "－", "〜"],
        ["～", "・", "•", "§"],
        ["¡", "¿", "^", "`"],
        ["＃", "％", "＆", "＊"],
        ["＋", "＝", "／", "＼"],
        ["＠", "＾", "＿", "｜"],
        ["．", "＄", "￥", "￡"],
        ["¢", "₩", "₽", "→"],
        ["○", "☆", "♪", "〒"]
    ]
    static let punctuation = columns.flatMap { $0 }

    static let pairedSymbols = [
        ["（", "）"], ["“", "”"], ["《", "》"], ["【", "】"],
        ["「", "」"], ["『", "』"], ["(", ")"], ["[", "]"], ["{", "}"], ["<", ">"],
        ["‘", "’"], ["〔", "〕"], ["〈", "〉"], ["［", "］"],
        ["｛", "｝"], ["＜", "＞"], ["«", "»"]
    ]

    // Writing-convention hints, not language restrictions on Unicode characters.
    private static let cjkBadges = Set("，。？！、；：（）“”‘’《》〈〉【】「」『』［］｛｝〔〕＜＞＂＇．".map(String.init))
    private static let englishBadges = Set(".,?!:;()[]{}<>".map(String.init) + ["'", "\""])
    static func badge(for symbol: String) -> String? {
        if cjkBadges.contains(symbol) { return "中日" }
        if englishBadges.contains(symbol) { return "英" }
        return nil
    }
}

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
        ["~", "|", "·", "——"]
    ]
    static let punctuation = columns.flatMap { $0 }
}

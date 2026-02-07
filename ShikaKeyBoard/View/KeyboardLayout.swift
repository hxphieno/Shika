//
//  KeyboardLayout.swift
//  ShikaKeyBoard
//
//  Created by ShiKa on 2026/1/30.
//

import Foundation

enum KeyboardMode {
    case lowercase
    case uppercase
}

struct KeyboardLayout {
    
    // keysLayout
    static let lowercase: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", "あ"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]
    
    // keysCapsLockLayout
    static let uppercase: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L", "—"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]
    
    static let lowCaseLetter: [String] = [
        "a","b","c","d","e","f","g","h","i","j",
        "k","l","m","n","o","p","q","r",
        "s","t","u","v","w","x","y","z"]

    static let punctuation: [String] = [
        "，", "。", "：", "？", "「」", "【】", "《》", "！", "@", "#", "¥", "“”", "……",
        "&", "*", "（）", "——", "｜", "、", "；", "：", "‘’"
    ]
}

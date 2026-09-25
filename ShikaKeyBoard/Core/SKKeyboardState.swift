import Foundation

/// The controller owns this state; views only render it and emit user intent.
struct SKKeyboardState {
    var scheme: SKInputScheme
    var languageMode: SKChineseJapaneseMode = .mixed
    var layout: SKKeyboardLayoutType = .alphabet
}

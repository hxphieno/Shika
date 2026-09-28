import Foundation

enum SKShuangpinScheme {
    // Keep the internal schema ID stable so existing Rime user learning is retained.
    // Its generated spelling table and display name now use Ziranma.
    static let configuration = SKInputConfiguration(schemaID: "shika_flypy",
        inputPolicy: .chineseRomanization, spelling: .doublePinyin)
}

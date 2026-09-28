import Foundation

/// Small, curated offline vocabulary. Matching decoded words lets both Chinese
/// spelling schemes share the same aliases and output preferences.
struct SKSpecialCandidates {
    // Session-owned selection ID, separate from native and correction IDs.
    static let candidateIndex = Int.min
    private let syllables: [String: String]

    init(resourceURL: URL? = Bundle.main.url(forResource: "RimeData", withExtension: "bundle")) {
        if let resourceURL,
           let data = try? Data(contentsOf: resourceURL.appendingPathComponent("correction-syllables.json")),
           let mapping = try? JSONDecoder().decode([String: String].self, from: data) {
            syllables = mapping
        } else { syllables = [:] }
    }

    func suggestion(for state: SKEngineState, configuration: SKInputConfiguration,
                    isDisplayable: (String) -> Bool) -> SKCandidate? {
        guard configuration.language == .chinese, state.page == 0,
              !state.input.isEmpty, state.committedText.isEmpty,
              !state.preedit.unicodeScalars.contains(where: { $0.value > 127 }) else { return nil }
        for candidate in state.candidates.prefix(5) {
            guard let output = Self.outputs[candidate.text],
                  candidate.consumedInputCount.map({ $0 == state.input.count }) ?? true,
                  configuration.spelling.isExact(comment: candidate.comment, input: state.input, syllables: syllables),
                  isDisplayable(output) else { continue }
            return SKCandidate(index: Self.candidateIndex, text: output, comment: candidate.text,
                               consumedInputCount: state.input.count)
        }
        return nil
    }

    // Authored for Shika. Keep one preferred result per word to avoid crowding
    // the candidate strip; aliases can share a result without extra rows.
    private static let outputs: [String: String] = [
        "逗号": "，", "句号": "。", "顿号": "、", "问号": "？", "感叹号": "！", "叹号": "！",
        "冒号": "：", "分号": "；", "省略号": "……", "破折号": "——",
        "左括号": "（", "右括号": "）", "左引号": "“", "右引号": "”",
        "书名号": "《》", "引号": "“”", "括号": "（）",
        "百分号": "%", "加号": "+", "减号": "−", "乘号": "×", "除号": "÷", "等号": "=",
        "摄氏度": "℃", "度数": "°", "人民币": "¥", "美元": "$", "欧元": "€",
        "烟花": "🎆", "焰火": "🎆", "礼花": "🎉", "庆祝": "🎉", "生日": "🎂", "蛋糕": "🎂",
        "礼物": "🎁", "气球": "🎈", "红包": "🧧", "新年": "🧧", "圣诞树": "🎄",
        "微笑": "😊", "大笑": "😆", "笑哭": "😂", "开心": "😄", "大哭": "😭", "哭泣": "😢",
        "难过": "😢", "生气": "😠", "愤怒": "😡", "惊讶": "😮", "害羞": "☺️", "思考": "🤔",
        "睡觉": "😴", "困了": "🥱", "亲亲": "😘", "拥抱": "🤗", "爱心": "❤️", "心碎": "💔",
        "点赞": "👍", "鼓掌": "👏", "握手": "🤝", "祈祷": "🙏", "加油": "💪", "胜利": "✌️",
        "太阳": "☀️", "月亮": "🌙", "星星": "⭐", "彩虹": "🌈", "下雨": "🌧️", "雪花": "❄️",
        "火焰": "🔥", "玫瑰": "🌹", "樱花": "🌸", "鲜花": "💐", "四叶草": "🍀",
        "小猫": "🐱", "小狗": "🐶", "兔子": "🐰", "熊猫": "🐼", "狐狸": "🦊", "蝴蝶": "🦋",
        "苹果": "🍎", "西瓜": "🍉", "草莓": "🍓", "樱桃": "🍒", "咖啡": "☕", "啤酒": "🍺",
        "干杯": "🥂", "汉堡": "🍔", "披萨": "🍕", "寿司": "🍣", "米饭": "🍚",
        "足球": "⚽", "篮球": "🏀", "音乐": "🎵", "飞机": "✈️", "火箭": "🚀", "汽车": "🚗",
        "手机": "📱", "电脑": "💻", "相机": "📷", "灯泡": "💡", "奖杯": "🏆", "闹钟": "⏰"
    ]
}

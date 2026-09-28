import Foundation

/// Run with the production Rime adapter and precompiled dictionary.
@main struct SpecialCandidatesRuntimeChecks {
    @MainActor static func main() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let user = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let mapping = try JSONDecoder().decode([String: String].self,
            from: Data(contentsOf: resources.appendingPathComponent("correction-syllables.json")))
        let provider = SKSpecialCandidates(resourceURL: resources)
        let full = SKInputConfiguration(schemaID: "shika_pinyin", inputPolicy: .chineseRomanization, spelling: .fullPinyin)
        let double = SKInputConfiguration(schemaID: "shika_flypy", inputPolicy: .chineseRomanization, spelling: .doublePinyin)
        var checks = 0
        func expect(_ value: Bool, _ label: String) {
            checks += 1
            guard value else { fatalError("FAIL: \(label)") }
            print("PASS: \(label)")
        }
        let engine = try SKRimeEngine(configuration: full, resourceURL: resources, userURL: user)
        var output = "", marked = ""
        let session = SKInputSession(engine: engine, configuration: full, insertText: { output += $0 }, deleteText: {},
            updateComposition: { marked = $0 }, specialCandidates: provider)
        func type(_ code: String) { for c in code { session.type(String(c)) } }
        for config in [full, double] {
            try session.switchConfiguration(to: config)
            for (reading, word, symbol) in [("dou hao", "逗号", "，"), ("yan hua", "烟花", "🎆"),
                ("ju hao", "句号", "。"), ("sheng ri", "生日", "🎂"), ("ai xin", "爱心", "❤️"),
                ("sheng lue hao", "省略号", "……"), ("wen hao", "问号", "？"), ("sheng li", "胜利", "✌️")] {
                let code = reading.split(separator: " ").map { config.spelling == .fullPinyin ? String($0) : mapping[String($0)]! }.joined()
                session.cancel(); output = ""; type(code)
                let rows = session.state.candidates
                print("\(config.schemaID) \(code): \(rows.prefix(6).map { "\($0.text){\($0.comment)}" })")
                expect(rows.count >= 3 && rows[2].text == symbol, "\(config.schemaID): \(word) symbol is third")
                let before = marked
                session.loadMoreCandidates()
                expect(marked == before && output.isEmpty && session.state.candidates[2].text == symbol,
                       "\(word) expansion preserves composition and third position")
                expect(session.state.candidates.filter { $0.text == symbol }.count == 1, "\(word) expansion has one symbol")
                session.select(session.state.candidates[2])
                expect(output == symbol && marked.isEmpty && session.state.input.isEmpty, "\(word) commits only symbol once")
                type(code); session.type(" ")
                expect(output == symbol + rows[0].text, "\(word) next input and normal space commit still work")
            }
            session.cancel(); output = ""
            let phrase = config.spelling == .fullPinyin ? "yanhuabiaoyan" : "yjhxbnyj"
            type(phrase)
            expect(!session.state.candidates.contains { $0.index == SKSpecialCandidates.candidateIndex },
                   "\(config.schemaID): longer phrase is not replaced by prefix emoji")
        }
        print("PASS: \(checks) real Rime special-candidate checks")
    }
}

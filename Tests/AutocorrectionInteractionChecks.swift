import Foundation

/// State/commit checks use the real production bridge and input policy.
@main struct AutocorrectionInteractionChecks {
    @MainActor static func main() throws {
        setbuf(stdout, nil)
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let user = URL(fileURLWithPath: CommandLine.arguments[2])
        let engine = try SKRimeEngine(configuration: SKInputScheme.chineseJapanese.configuration, resourceURL: resources, userURL: user)
        var output = "", count = 0
        let session = SKInputSession(engine: engine, configuration: SKInputScheme.chineseJapanese.configuration, insertText: { output += $0 }, deleteText: { if !output.isEmpty { output.removeLast() } })
        func expect(_ ok: Bool, _ label: String) { if !ok { print("FAIL \(label), output=\(output), state=\(session.state)"); exit(1) }; count += 1; print("PASS \(label)") }
        func type(_ text: String) { for c in text { session.type(String(c)) } }
        func reset(_ schema: String, _ code: String) throws { session.cancel(); output = ""; try session.switchConfiguration(to: SKInputScheme(schemaID: schema)!.configuration); type(code) }
        for (schema, code, target) in [("shika_pinyin", "nohao", "你好"), ("shika_pinyin", "zhnogguo", "中国"), ("shika_pinyin", "zhonguo", "中国"), ("shika_pinyin", "zhongguoo", "中国"), ("shika_flypy", "nijc", "你好"), ("shika_flypy", "niihc", "你好"), ("shika_flypy", "nhc", "你好"), ("shika_flypy", "svgo", "中国")] {
            try reset(schema, code)
            guard let candidate = session.state.candidates.first(where: {$0.text == target}) else { fatalError("Missing \(code) -> \(target)") }
            session.select(candidate)
            expect(output == target && session.state.input.isEmpty, "click \(schema) \(code) commits \(target) once")
            session.commitPending(); expect(output == target, "commit is drained")
        }
        for suffix in [" ", "\n", "，", "1", "A"] {
            try reset("shika_pinyin", "zhnogguo")
            let first = session.state.candidates[0].text
            session.type(suffix)
            expect(output == first + (suffix == " " ? "" : suffix), "\(suffix.debugDescription) follows visible first")
        }
        try reset("shika_pinyin", "zhnogguo");session.commitRaw()
        expect(output == "zhnogguo" && session.state.input.isEmpty, "raw input preserves typo")
        try reset("shika_flypy", "niihc");session.deleteBackward()
        expect(session.state.input == "niih" && output.isEmpty, "backspace changes actual raw input")
        session.cancel(); expect(session.state.input.isEmpty && output.isEmpty, "cancel never commits a suggestion")
        try reset("shika_pinyin", "zhnogguo");let first = session.state.candidates[0].text
        try session.switchConfiguration(to: SKInputScheme.shuangpin.configuration);expect(output == first, "scheme switch commits visible correction once")
        type("nihc");session.type(" ");expect(output == first + "你好", "new scheme starts clean")
        try reset("shika_pinyin", "ni");session.changePage(backward: false)
        let second = session.state.candidates[1];session.select(second)
        expect(output == second.text, "native page indexes remain valid")
        try reset("shika_pinyin", "nohao");session.changePage(backward: false);session.changePage(backward: true)
        let restored = session.state.candidates.first(where: {$0.text == "你好"})!
        session.select(restored);expect(output == "你好", "correction survives page round trip")
        try reset("shika_pinyin", "nihaoshijie")
        session.select(session.state.candidates.first(where: {$0.text == "你好"})!)
        expect(output.isEmpty && session.state.preedit.contains("你好"), "partial choice stays in native composition")
        session.type(" ");expect(output == "你好世界", "partial choice then space produces full sentence once")
        try reset("shika_pinyin", "lujianmiao")
        for target in ["鹿", "键", "喵"] {
            var found: SKCandidate?
            for _ in 0..<100 {
                if let candidate = session.state.candidates.first(where: {$0.text == target}) { found = candidate;break }
                if session.state.isLastPage {break};session.changePage(backward: false)
            }
            guard let found else {fatalError("missing learning character \(target)")};session.select(found)
        }
        expect(output == "鹿键喵", "new user phrase learned through native segments")
        try reset("shika_pinyin", "lujianmiao")
        expect(session.state.candidates.first?.text == "鹿键喵", "exact learned word protected from corrections")
        print("COMPLETE: \(count) correction interaction assertions")
    }
}

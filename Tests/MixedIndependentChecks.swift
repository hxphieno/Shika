import Foundation

/// Independent state/consumption checks. No candidate mocks and no UIKit.
@main struct MixedIndependentChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 5 else { fatalError("resources user report behavior|learn|probe") }
        let resources = URL(fileURLWithPath: args[1])
        let user = URL(fileURLWithPath: args[2])
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        var checks: [[String: Any]] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            checks.append(["name": name, "passed": ok, "detail": detail])
            print("\(ok ? "PASS" : "FAIL"): \(name) \(detail)")
        }
        let mixedConfig = SKChineseJapaneseScheme.configuration(for: .mixed)
        let engine = try SKMixedEngine(resources: resources, userDirectory: user)
        func type(_ raw: String, into target: any SKInputEngine) -> SKEngineState {
            var state = SKEngineState()
            for scalar in raw.unicodeScalars { state = target.process(key: Int32(scalar.value)) }
            return state
        }
        func all(_ target: any SKInputEngine) -> [SKCandidate] {
            var result: [SKCandidate] = [], index = 0
            for _ in 0..<10 {
                let page = target.candidatePage(startingAt: index, limit: 13)
                result += page.candidates
                if !page.hasMore { break }
                guard page.nextIndex > index else { break }
                index = page.nextIndex
            }
            return result
        }
        func reset(_ raw: String) -> SKEngineState {
            _ = engine.clear(); return type(raw, into: engine)
        }
        if args[4] == "learn" || args[4] == "probe" {
            let learning = user.appendingPathComponent("mixed-learning.json")
            let learnedChoice = "今天也有難う"
            if args[4] == "learn" {
                let before = (try? Data(contentsOf: learning))
                _ = reset("jintianyearigatou")
                let choices = all(engine)
                check("learning target starts below first rank", choices.first?.text != learnedChoice && choices.contains(where: {$0.text == learnedChoice}))
                var commitsCorrect = true
                for _ in 0..<5 {
                    _ = reset("jintianyearigatou")
                    if let desired = all(engine).first(where: { $0.text == learnedChoice }) {
                        commitsCorrect = commitsCorrect && engine.selectCandidate(at: desired.index).committedText == desired.text
                    } else { commitsCorrect = false }
                }
                check("learn five explicit joint selections", commitsCorrect)
                let data = try Data(contentsOf: learning)
                let records = try JSONDecoder().decode([String: Int].self, from: data)
                check("learning writes word and language-transition records", records.keys.contains(where: {$0.hasPrefix("w:")}) && records.keys.contains(where: {$0.hasPrefix("p:")}) && data != before)
                _ = reset("jintianyearigatou")
                check("learning promotes chosen mixed sentence to first rank", all(engine).first?.text == learnedChoice)
            } else {
                let before = try Data(contentsOf: learning)
                let records = try JSONDecoder().decode([String: Int].self, from: before)
                check("new process loads nonempty persisted learning", !records.isEmpty)
                _ = reset("jintianyearigatou")
                check("new process preserves learned first ranking", all(engine).first?.text == learnedChoice)
                _ = engine.clear()
                check("typing/browsing/cancel do not write learning", try Data(contentsOf: learning) == before)
            }
        } else {
            let raw = "jintianyearigatou"
            let initial = reset(raw)
            check("raw composition contains all input and no eager commit", initial.input == raw && initial.committedText.isEmpty)
            let candidates = all(engine)
            check("candidate IDs unique across uneven pages", Set(candidates.map(\.index)).count == candidates.count)
            check("candidate IDs contiguous across pages", candidates.map(\.index) == Array(0..<candidates.count))
            check("zero-size page does not advance", engine.candidatePage(startingAt: 8, limit: 0).nextIndex == min(8, candidates.count))
            check("out-of-range page is safely empty", engine.candidatePage(startingAt: Int.max, limit: 40).candidates.isEmpty)
            for invalid in [-1, Int.max] {
                let result = engine.selectCandidate(at: invalid)
                check("invalid candidate \(invalid) preserves composition", result.input == initial.input && result.preedit == initial.preedit && result.committedText.isEmpty)
            }
            let page1 = engine.changePage(backward: false)
            check("page navigation preserves raw input", page1.input == raw && page1.committedText.isEmpty)
            check("expanded and paged IDs agree", page1.candidates == Array(candidates.dropFirst(8).prefix(8)))
            _ = engine.changePage(backward: true)
            check("browsing does not reorder candidate IDs", all(engine) == candidates)

            if let prefix = candidates.first(where: {$0.text == "今天也"}) {
                var result = engine.selectCandidate(at: prefix.index)
                check("partial keeps original raw offsets", result.input == raw && result.preedit == "今天也arigatou" && result.committedText.isEmpty)
                result = engine.process(key: 0xff0d)
                check("Return preserves selected prefix plus raw tail", result.committedText == "今天也arigatou" && result.input.isEmpty)
                check("Return has no duplicate commit", engine.process(key: 0xff0d).committedText.isEmpty)
                _ = reset(raw); _ = engine.selectCandidate(at: prefix.index)
                for _ in "arigatou" { result = engine.process(key: 0xff08) }
                check("tail deletion leaves selected prefix", result.input == "jintianye" && result.preedit == "今天也")
                result = engine.process(key: 0xff08)
                check("boundary deletion restores raw spelling without dropping it", result.input == "jintianye" && result.preedit != "今天也" && result.preedit.contains(where: {$0.isASCII && $0.isLetter}))
                for _ in 0..<30 where !result.input.isEmpty { result = engine.process(key: 0xff08) }
                check("deletion eventually clears locked and raw segments", result.input.isEmpty && result.preedit.isEmpty && result.committedText.isEmpty)
            } else { check("partial prefix exists", false) }

            _ = reset("ni'")
            let repeatedText = all(engine).filter {$0.text == "你"}
            check("same text with distinct coverage has distinct candidate IDs", repeatedText.count >= 2 && Set(repeatedText.map(\.index)).count == repeatedText.count)
            if let full = repeatedText.first, let partial = repeatedText.last, full.index != partial.index {
                let fullResult = engine.selectCandidate(at: full.index)
                _ = reset("ni'")
                let partialResult = engine.selectCandidate(at: partial.index)
                check("equal output candidates retain different consumption", fullResult.committedText == "你" && fullResult.input.isEmpty && partialResult.committedText.isEmpty && partialResult.preedit == "你'", "full=\(fullResult.committedText), partial=\(partialResult.preedit)")
            }
            _ = reset("xi'an")
            let separated = all(engine)
            check("explicit Chinese syllable boundary retains 西安", separated.contains(where: {$0.text == "西安"}))
            check("explicit Chinese syllable boundary excludes single-syllable xian", !separated.contains(where: {["先", "现", "线"].contains($0.text)}), separated.prefix(8).map(\.text).joined(separator: "|"))
            let multiRaw = "zhegesugoiwoxihuan"
            _ = reset(multiRaw)
            if let chinese = all(engine).first(where: {$0.text == "这个"}) {
                _ = engine.selectCandidate(at: chinese.index)
                if let japanese = all(engine).first(where: {$0.text == "すごい"}) {
                    var locked = engine.selectCandidate(at: japanese.index)
                    check("two partial selections retain both language prefixes", locked.input == multiRaw && locked.preedit == "这个すごいwoxihuan" && locked.committedText.isEmpty)
                    for _ in "woxihuan" {locked = engine.process(key: 0xff08)}
                    check("deleting tail preserves two locked prefixes", locked.input == "zhegesugoi" && locked.preedit == "这个すごい")
                    locked = engine.process(key: 0xff08)
                    check("deleting Japanese lock restores raw without consuming it", locked.input == "zhegesugoi" && locked.preedit.hasPrefix("这个") && locked.preedit.contains(where: {$0.isASCII && $0.isLetter}))
                    for _ in 0..<20 where locked.input.count > "zhege".count {locked = engine.process(key: 0xff08)}
                    check("deleting restored Japanese spelling keeps Chinese lock", locked.input == "zhege" && locked.preedit == "这个")
                    locked = engine.process(key: 0xff08)
                    check("second boundary restores Chinese spelling too", locked.input == "zhege" && locked.preedit.contains(where: {$0.isASCII && $0.isLetter}))
                } else {check("second-language partial candidate exists", false)}
            } else {check("first-language partial candidate exists", false)}

            let router = try SKConversionEngine(configuration: mixedConfig, resourceURL: resources, userURL: user)
            var output = "", marked = "", deletes = 0
            let session = SKInputSession(engine: router, configuration: mixedConfig,
                insertText: { output += $0 }, deleteText: { deletes += 1 }, updateComposition: { marked = $0 })
            func enter(_ raw: String) { for c in raw {session.type(String(c))} }
            func fresh() {session.cancel();output = ""}
            fresh();enter(raw);session.type("\n")
            check("session Return emits original letters without newline", output == raw && marked.isEmpty)
            session.type("\n");check("idle Return inserts newline", output == raw + "\n")
            session.deleteBackward();check("idle delete reaches document", deletes == 1)
            for literal in ["，", "1", "🙂"] {
                fresh();enter(raw + "q");session.type(literal)
                check("literal flush preserves undecoded tail: \(literal)", output.hasSuffix("q" + literal) && session.state.input.isEmpty, output)
            }
            for configuration in [SKChineseJapaneseScheme.configuration, SKChineseJapaneseScheme.configuration(for: .japanese), SKInputScheme.shuangpin.configuration] {
                try session.switchConfiguration(to: mixedConfig)
                fresh();enter(raw + "q");session.loadMoreCandidates()
                if let prefix = session.state.candidates.first(where: {$0.text == "今天也"}) {session.select(prefix)}
                try session.switchConfiguration(to: configuration)
                check("mode change flush retains selected prefix and raw tail: \(configuration.schemaID)", output.hasPrefix("今天也") && output.hasSuffix("q") && marked.isEmpty, output)
            }
            for (configuration, code, expected) in [
                (SKChineseJapaneseScheme.configuration, "nihao", "你好"),
                (SKChineseJapaneseScheme.configuration(for: .japanese), "arigatou", "ありがとう"),
                (SKInputScheme.shuangpin.configuration, "nihc", "你好")
            ] {
                try session.switchConfiguration(to: configuration);fresh();enter(code)
                check("pure mode retains expected candidates: \(configuration.schemaID)", session.state.candidates.contains(where: {$0.text == expected}))
                if configuration.language == .chinese {
                    check("pure Chinese has no mixed Japanese labels", session.state.candidates.allSatisfy { !$0.comment.contains("日文") && !$0.comment.contains("中日") })
                }
            }
            try session.switchConfiguration(to: mixedConfig);fresh();enter("ko")
            session.type("ー");enter("hi");session.type("ー")
            check("mixed long-vowel UI key stays in composition", output.isEmpty && session.state.input == "ko-hi-", "output=\(output), input=\(session.state.input)")
            check("mixed long-vowel Japanese word is selectable", session.state.candidates.contains(where: {$0.text == "コーヒー"}))
            fresh();session.type("ー");session.type("-")
            check("idle mixed long vowels remain literal punctuation", output == "ー-" && session.state.input.isEmpty)
            fresh();enter("ni'")
            for _ in 0..<8 where !session.state.isLastPage {session.loadMoreCandidates()}
            check("candidate expansion preserves equal-text different-coverage choices", session.state.candidates.filter {$0.text == "你"}.count >= 2)
            fresh();enter(raw);session.commitRaw();session.commitRaw()
            check("raw commit clears once", output == raw && marked.isEmpty)

            let longRaw = String(repeating: "q", count: 113)
            _ = reset(longRaw)
            let longResult = engine.process(key: 0xff0d)
            check("bounded decoding keeps all 113 raw letters", longResult.committedText == longRaw)
            _ = reset(String(repeating: "nihao", count: 20) + "q")
            let longFlush = engine.commit()
            check("long supported-input flush preserves opaque tail", longFlush.committedText.hasSuffix("q") && longFlush.input.isEmpty)
            check("clear removes both selected and previous context", engine.clear().input.isEmpty && all(engine).isEmpty)
        }
        let failures = checks.filter { !($0["passed"] as! Bool) }.count
        let report: [String: Any] = ["checks": checks, "failed": failures, "mode": args[4], "platform": "macOS production engines, no UIKit"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: args[3]))
        print("Independent mixed: \(checks.count) checks, \(failures) failures")
        if failures > 0 {exit(1)}
    }
}

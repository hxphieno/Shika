import Foundation

/// Independent engine acceptance: real bundled lexicons/Rime, no UI changes.
@main struct SentenceLimitIndependentChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let resources = URL(fileURLWithPath: args[1]), root = URL(fileURLWithPath: args[2])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let user = root.appendingPathComponent("user")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        var checks = [[String: Any]](), samples = [[String: Any]]()
        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            checks.append(["label": label, "passed": passed, "detail": detail])
        }
        let chinese = try SKMixedChineseLexicon(resources: resources)
        let decoder = try SKMixedDecoder(resources: resources)
        let native = try SKRimeSession(sharedPath: resources.path, userPath: user.path, schema: "shika_pinyin")
        func query(_ code: String) -> [SKCandidate] {
            let data = native.replaceInput(code)
            return (data["candidates"] as? [[String: Any]] ?? []).compactMap { row in
                guard let text = row["text"] as? String else { return nil }
                return SKCandidate(index: 0, text: text, comment: row["comment"] as? String ?? "")
            }
        }
        func wholeWords(_ code: String) -> Set<String> {
            var words = Set(chinese.words(for: code.replacingOccurrences(of: "'", with: "")).map(\.text))
            let reading = decoder.japanese.reading(code)
            if reading.pending.isEmpty { words.formUnion(decoder.japanese.words(for: reading.kana).map(\.text)) }
            return words
        }
        let codes = ["haibiandianqiyanhuo", "jintianyearigatou", "jintianyearigadou", "mingtianqudongjing", "woaini", "nihaoshijie", "woxiangchifan", "arigatou", "konnichiha", "zhonghuarenmingongheguo", "jisuanjikexue", "haibian", "fuyuanxiaoqu", "hai'bian'dian'qi'yan'huo"]
        for code in codes {
            let paths = decoder.decode(code, context: nil, native: query(code), chineseQuery: query, bonus: { _, _ in 0 })
            let words = wholeWords(code)
            // Corrections are dictionary words; inspect corrected flag to avoid
            // classifying genuine corrected full-word alternatives as sentences.
            let generated = paths.filter { $0.consumed == code.count && !words.contains($0.text) && !$0.segments.contains(where: \.corrected) }
            check("\(code): no more than six generated full sentences", generated.count <= 6, "\(generated.count)")
            check("\(code): after six suggestions all partial choices are single words", paths.dropFirst(6).filter { $0.consumed < code.count }.allSatisfy { $0.segments.count == 1 })
            check("\(code): candidate identities unique", Set(paths.map { "\($0.consumed):\($0.text)" }).count == paths.count)
            samples.append(["input": code, "generatedCount": generated.count, "candidates": paths.map { ["text": $0.text, "consumed": $0.consumed, "segments": $0.segments.count] as [String: Any] }])
            if code == "fuyuanxiaoqu" {
                let longWords = words.filter { $0.count >= 4 }
                check("more-than-six long-word fixture exists", longWords.count >= 7)
                check("all seven genuine long homophones survive cap", longWords.isSubset(of: Set(paths.filter { $0.consumed == code.count }.map(\.text))), paths.map(\.text).joined(separator: "|"))
            }
            if code == "zhonghuarenmingongheguo" {
                check("long dictionary word fixture exists", words.contains("中华人民共和国"))
                check("long dictionary word retained", paths.contains { $0.text == "中华人民共和国" && $0.consumed == code.count })
            }
        }
        let mixed = try SKMixedEngine(resources: resources, userDirectory: user)
        func type(_ code: String, into engine: SKInputEngine) -> SKEngineState {
            _ = engine.clear(); var state = SKEngineState()
            for scalar in code.unicodeScalars { state = engine.process(key: Int32(scalar.value)) }
            return state
        }
        func all(_ engine: SKInputEngine, pageSize: Int) -> [SKCandidate] {
            var result = [SKCandidate](), cursor = 0
            for _ in 0..<200 {
                let page = engine.candidatePage(startingAt: cursor, limit: pageSize)
                result += page.candidates
                if !page.hasMore { break }
                guard page.nextIndex > cursor else { check("pagination advances", false); break }
                cursor = page.nextIndex
            }
            return result
        }
        let code = "haibiandianqiyanhuo"
        for (name, configuration, raw) in [("pinyin", SKChineseJapaneseScheme.configuration, code), ("shuangpin", SKShuangpinScheme.configuration, "hdbmdmqiyjho")] {
            let engine = try SKRimeEngine(configuration: configuration, resourceURL: resources, userURL: user)
            _ = type(raw, into: engine)
            let current = all(engine, pageSize: 7)
            check("\(name): prefix 海边 remains accessible after at most six full alternatives", (current.firstIndex { $0.text == "海边" } ?? Int.max) <= 6, current.prefix(7).map(\.text).joined(separator: "|"))
            if let row = current.first(where: { $0.text == "海边" }) {
                let state = engine.selectCandidate(at: row.index)
                check("\(name): prefix selection keeps composition", state.committedText.isEmpty && state.preedit.hasPrefix("海边"), state.preedit)
                let confirmed = engine.process(key: 0xff0d)
                check("\(name): Return keeps selected prefix", confirmed.committedText.hasPrefix("海边"), confirmed.committedText)
            }
        }
        let initial = type(code, into: mixed)
        let rows = all(mixed, pageSize: 3)
        check("screenshot: 海边 immediately after six suggestions", rows.firstIndex { $0.text == "海边" } == 6, rows.prefix(12).map(\.text).joined(separator: "|"))
        check("screenshot: only six full sentence candidates across all pages", rows.filter { $0.consumedInputCount == code.count }.count == 6)
        check("screenshot: initial rows agree with expanded pages", initial.candidates == Array(rows.prefix(initial.candidates.count)))
        check("pagination size does not change IDs or ordering", rows == all(mixed, pageSize: 64))
        let second = mixed.changePage(backward: false)
        check("next-page navigation follows same candidate IDs", second.candidates == Array(rows.dropFirst(8).prefix(8)))
        let first = mixed.changePage(backward: true)
        check("previous-page navigation retains original ordering", first.candidates == initial.candidates)
        if let prefix = rows.first(where: { $0.text == "海边" }) {
            let selected = mixed.selectCandidate(at: prefix.index)
            check("prefix selection retains exact raw suffix", selected.preedit == "海边dianqiyanhuo" && selected.committedText.isEmpty, selected.preedit)
            let remainder = all(mixed, pageSize: 5)
            check("selected prefix exposes next word 电器", remainder.contains { $0.text == "电器" })
            let raw = mixed.process(key: 0xff0d)
            check("Return preserves selected prefix and raw suffix", raw.committedText == "海边dianqiyanhuo", raw.committedText)
        } else { check("prefix selectable", false) }
        _ = type(code, into: mixed)
        var accepted = [String]()
        for word in ["海边", "电器", "烟火"] {
            if let row = all(mixed, pageSize: 7).first(where: { $0.text == word }) {
                accepted.append(mixed.selectCandidate(at: row.index).committedText)
            } else { check("word-by-word candidate \(word) available", false); break }
        }
        check("word-by-word selection commits whole intended phrase", accepted.joined() == "海边电器烟火", accepted.joined())
        _ = type(code, into: mixed)
        var customOutput = ""
        for (word, expectedPreedit) in [("海边", "海边dianqiyanhuo"), ("点", "海边点qiyanhuo"), ("起", "海边点起yanhuo"), ("烟火", "")] {
            let choices = all(mixed, pageSize: 7)
            guard let row = choices.first(where: { $0.text == word }) else {
                check("unpredicted sentence: selectable \(word)", false, choices.map(\.text).joined(separator: "|")); break
            }
            let selected = mixed.selectCandidate(at: row.index)
            check("unpredicted sentence: \(word) keeps exact remaining code", selected.preedit == expectedPreedit, selected.preedit)
            customOutput += selected.committedText
        }
        check("unpredicted sentence can be assembled word by word", customOutput == "海边点起烟火", customOutput)
        let beforeSpace = type(code, into: mixed)
        let space = mixed.process(key: 0x20)
        check("space still commits first sentence", space.committedText == beforeSpace.candidates.first?.text)
        let failures = checks.filter { !($0["passed"] as! Bool) }
        let result: [String: Any] = ["checks": checks, "failed": failures, "count": checks.count, "samples": samples]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("independent.json"))
        print("Sentence limit independent: \(checks.count-failures.count)/\(checks.count)")
        if !failures.isEmpty { exit(1) }
    }
}

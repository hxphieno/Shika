import Foundation

@main struct PrefixCandidateChecks {
    @MainActor static func main() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let user = URL(fileURLWithPath: CommandLine.arguments[2])
        let engines: [(String, any SKInputEngine, SKInputConfiguration)] = [
            ("pinyin", try SKRimeEngine(configuration: SKChineseJapaneseScheme.configuration, resourceURL: resources, userURL: user), SKChineseJapaneseScheme.configuration),
            ("shuangpin", try SKRimeEngine(configuration: SKShuangpinScheme.configuration, resourceURL: resources, userURL: user), SKShuangpinScheme.configuration),
            ("japanese", try SKJapaneseEngine(resources: resources, userDirectory: user), SKChineseJapaneseScheme.configuration(for: .japanese)),
            ("mixed", try SKMixedEngine(resources: resources, userDirectory: user), SKChineseJapaneseScheme.configuration(for: .mixed))
        ]
        var failures: [String] = [], checks = 0, timings: [Double] = []
        func check(_ ok: Bool, _ message: String) {
            checks += 1
            if !ok { failures.append(message); print("FAIL: \(message)") }
        }
        func type(_ input: String, _ engine: any SKInputEngine) -> SKEngineState {
            _ = engine.clear(); var state = SKEngineState()
            for byte in input.utf8 {
                let start = DispatchTime.now().uptimeNanoseconds
                state = engine.process(key: Int32(byte))
                timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                check(state.committedText.isEmpty, "typing must not commit: \(input)")
            }
            return state
        }
        func all(_ engine: any SKInputEngine) -> [SKCandidate] {
            // Native correction choices have negative IDs and exist only on
            // the presented page; pagination enumerates the underlying lexicon.
            var result = engine.process(key: 0).candidates, next = 0
            var seen = Set(result.map(\.index))
            for _ in 0..<8 {
                let page = engine.candidatePage(startingAt: next, limit: 64)
                result += page.candidates.filter { seen.insert($0.index).inserted }
                if !page.hasMore || page.nextIndex <= next { break }
                next = page.nextIndex
            }
            return result
        }
        let coldMixed = type("wsm", engines.last!.1)
        check(coldMixed.candidates.first?.text == "为什么", "fresh mixed wsm: 为什么 is the first candidate")
        for (mode, engine, configuration) in engines {
            let cases: [(String, [String])]
            switch mode {
            case "pinyin": cases = [("w", ["我", "为", "万", "唯"]), ("wsm", ["为什么"]), ("wei'sm", ["为什么"]), ("w's'm", ["为什么"]), ("nh", ["你好"]), ("nih", ["你好"]), ("zhon", ["中"]), ("nihao", ["你好"])]
            case "mixed": cases = [("w", ["我", "为", "万", "唯"]), ("wsm", ["为什么"]), ("wei'sm", ["为什么"]), ("w's'm", ["为什么"]), ("nh", ["你好"]), ("nih", ["你好"]), ("zhon", ["中"]), ("nihao", ["你好"]), ("watash", ["私"]), ("nihong", ["日本語"]), ("gakk", ["学校"])]
            case "shuangpin": cases = [("w", ["我", "为", "万", "唯"]), ("wzufm", ["为什么"]), ("nihk", ["你好"]), ("v", ["这", "中"])]
            default: cases = [("w", []), ("k", []), ("sh", []), ("ky", []), ("watash", ["私"]), ("nihong", ["日本語"]), ("gakk", ["学校"])]
            }
            for (raw, expected) in cases {
                let state = type(raw, engine), candidates = all(engine)
                print(mode, raw, "first:", state.candidates.map(\.text), "count:", candidates.count)
                check(!state.candidates.isEmpty, "\(mode) \(raw): initial candidates")
                check(Set(candidates.map(\.index)).count == candidates.count, "\(mode) \(raw): stable unique IDs")
                check(engine.process(key: 0).input == raw, "\(mode) \(raw): browsing preserves input")
                for text in expected {
                    _ = type(raw, engine)
                    guard let choice = all(engine).first(where: { $0.text == text }) else {
                        check(false, "\(mode) \(raw): missing \(text)"); continue
                    }
                    let selected = engine.selectCandidate(at: choice.index)
                    check(selected.committedText == text && selected.input.isEmpty, "\(mode) \(raw): commit \(text) without raw suffix, got \(selected.committedText) / \(selected.preedit)")
                }
                _ = type(raw, engine)
                let returned = engine.process(key: 0xff0d)
                check(returned.committedText == raw && returned.input.isEmpty, "\(mode) \(raw): Return keeps original letters")
                _ = type(raw, engine)
                let deleted = engine.process(key: 0xff08)
                check(deleted.input == String(raw.dropLast()), "\(mode) \(raw): delete one original letter")
            }
            // Exercise the actual session routing, raw fallback and non-destructive paging.
            var inserted = "", marked = ""
            let session = SKInputSession(engine: engine, configuration: configuration,
                insertText: { inserted += $0 }, deleteText: {}, updateComposition: { marked = $0 })
            session.cancel()
            for letter in "w" { session.type(String(letter)) }
            check(session.state.candidates.contains { $0.text != "w" }, "\(mode): session has converted choices before raw fallback")
            let before = marked
            for _ in 0..<4 { session.loadMoreCandidates() }
            check(marked == before && inserted.isEmpty, "\(mode): expanding candidates is non-destructive")
            if mode != "japanese", let choice = session.state.candidates.first(where: { $0.text == "唯" }) {
                session.select(choice)
                check(inserted == "唯" && marked.isEmpty, "\(mode): expanded candidate selection replaces composition")
            } else if mode != "japanese" { check(false, "\(mode): session expanded 唯 missing") }
            session.cancel()
            inserted = ""
            let unfinished = mode == "japanese" ? "watash" : (mode == "shuangpin" ? "w" : "wsm")
            for letter in unfinished { session.type(String(letter)) }
            let first = session.state.candidates.first?.text ?? ""
            session.type(" ")
            check(!first.isEmpty && inserted == first && marked.isEmpty, "\(mode): space confirms the visible completion once")
            inserted = ""
            for letter in unfinished { session.type(String(letter)) }
            let beforePunctuation = session.state.candidates.first?.text ?? ""
            session.type("，")
            check(inserted == beforePunctuation + "，" && marked.isEmpty, "\(mode): punctuation flushes completed choice without a raw suffix")
        }
        let exact = type("wode", engines[0].1)
        check(exact.candidates.contains { $0.text == "我得" && $0.comment == "wo de" },
              "pinyin: wodei completion must not replace an exact wode homophone")
        let mixed = engines.last!.1
        _ = type("wsmq", mixed)
        if let prefix = all(mixed).first(where: { $0.text == "为什么" && $0.consumedInputCount == 3 }) {
            let selected = mixed.selectCandidate(at: prefix.index)
            check(selected.committedText.isEmpty && selected.preedit.replacingOccurrences(of: " ", with: "") == "为什么q", "mixed: abbreviation selection preserves raw remainder")
            check(mixed.process(key: 0xff0d).committedText == "为什么q", "mixed: Return preserves selected abbreviation and tail")
            _ = type("wsmq", mixed); _ = mixed.selectCandidate(at: prefix.index)
            _ = mixed.process(key: 0xff08)
            let restored = mixed.process(key: 0xff08)
            check(restored.input == "wsm" && !restored.candidates.isEmpty, "mixed: deleting locked prefix restores abbreviated spelling")
        } else { check(false, "mixed: selectable abbreviated prefix for wsmq") }
        let japanese = engines[2].1
        _ = type("watash", japanese)
        if let choice = all(japanese).first(where: { $0.text == "私" }) { _ = japanese.selectCandidate(at: choice.index) }
        let learned = try JSONDecoder().decode([String: [String: Int]].self, from: Data(contentsOf: user.appendingPathComponent("japanese-learning.json")))
        check(learned["わたし"]?["私"] != nil && learned["わた"]?["私"] == nil, "Japanese completion learns its completed reading")
        _ = type("watashq", japanese)
        check(all(japanese).isEmpty && japanese.process(key: 0xff0d).committedText == "watashq", "invalid Japanese tail keeps literal input instead of stale completions")
        // Composition-wide quotas must survive expansion and preserve the
        // engine's selection routes, especially non-contiguous native IDs.
        for (mode, engine, _) in engines {
            let raw = mode == "japanese" ? "watashihanihonjin" : (mode == "shuangpin" ? "wzufme" : "wsm")
            _ = type(raw, engine)
            let candidates = all(engine)
            let literals: Set<String> = mode == "japanese" ? ["わたしはにほんじん", "ワタシハニホンジン"] : []
            let converted = candidates.filter { !literals.contains($0.text) }
            for length in 2...3 {
                check(converted.filter { min(4, $0.text.count) == length }.count <= 6,
                    "\(mode): group \(length) never exceeds six across pages")
            }
            check(converted.filter { $0.text.count >= 4 }.count <= 12,
                "\(mode): at most six long recommendations plus six long dictionary words")
            check(converted.contains { $0.text.count == 1 }, "\(mode): single characters remain selectable")
            let groups = converted.dropFirst(6).map { min(4, $0.text.count) }
            check(zip(groups, groups.dropFirst()).allSatisfy { $0 >= $1 },
                "\(mode): after recommendations, longer words precede shorter words")
            let repeated = engine.candidatePage(startingAt: 8, limit: 40).candidates
            check(repeated == engine.candidatePage(startingAt: 8, limit: 40).candidates,
                "\(mode): repeated page requests preserve order and IDs")
            print("GROUPS", mode, raw, Array(candidates.prefix(24)).map { "\($0.text):\($0.consumedInputCount ?? -1)" })
        }
        for index in [0, 3] {
            let (mode, engine, configuration) = engines[index]
            _ = type("wsm", engine)
            let candidates = all(engine)
            check(candidates.filter { $0.text.count == 3 }.count == 6, "\(mode): WSM has exactly six three-character choices")
            check(candidates.filter { $0.text.count == 2 }.count == 6, "\(mode): WSM has exactly six two-character choices")
            check(candidates.firstIndex(where: { $0.text.count == 1 }) == 12, "\(mode): WSM reaches single characters at position thirteen")
            for (text, expected) in [("我", "我sm"), ("我是", "我是m")] {
                _ = type("wsm", engine)
                if let choice = all(engine).first(where: { $0.text == text }) {
                    let selected = engine.selectCandidate(at: choice.index)
                    check(selected.committedText.isEmpty, "\(mode): choosing \(text) leaves the tail marked")
                    check(engine.process(key: 0xff0d).committedText == expected, "\(mode): prefix selection preserves the exact raw tail")
                } else { check(false, "\(mode): missing prefix \(text)") }
            }
            var output = ""
            let session = SKInputSession(engine: engine, configuration: configuration, insertText: { output += $0 }, deleteText: {})
            session.cancel()
            for letter in "wsm" { session.type(String(letter)) }
            session.loadMoreCandidates()
            if let single = session.state.candidates.first(where: { $0.text == "我" }) {
                session.select(single); session.type("\n")
                check(output == "我sm", "\(mode): expanded grid routes a single character without swallowing sm")
            } else { check(false, "\(mode): expanded grid includes 我") }
        }
        _ = type("watashihanihonjin", japanese)
        if let choice = all(japanese).first(where: { $0.text == "私" && $0.consumedInputCount == 7 }) {
            let selected = japanese.selectCandidate(at: choice.index)
            check(selected.committedText.isEmpty && selected.preedit == "私hanihonjin", "Japanese prefix consumes its romanization, not one output character")
            check(japanese.process(key: 0xff0d).committedText == "私hanihonjin", "Japanese Return keeps selected prefix and raw tail")
            _ = type("watashihanihonjin", japanese)
            let current = all(japanese).first { $0.text == "私" && $0.consumedInputCount == 7 }!
            _ = japanese.selectCandidate(at: current.index)
            for _ in "hanihonjin" { _ = japanese.process(key: 0xff08) }
            let restored = japanese.process(key: 0xff08)
            check(restored.input == "watashi" && restored.preedit == "watashi", "Japanese delete at a selected boundary restores the original spelling")
        } else { check(false, "Japanese sentence includes selectable single-character prefix 私") }
        timings.sort()
        print("\(checks - failures.count)/\(checks) passed; key latency p95 \(timings[Int(Double(timings.count) * 0.95)]) ms, max \(timings.last ?? 0) ms")
        if !failures.isEmpty { exit(1) }
    }
}

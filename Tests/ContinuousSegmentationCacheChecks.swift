// Independent spies verify that cached parsing never caches native ranking.
import Foundation

@main struct ContinuousSegmentationCacheChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let resources = URL(fileURLWithPath: args[1])
        let config = SKInputConfiguration(schemaID: "shika_pinyin", inputPolicy: .chineseRomanization, spelling: .fullPinyin)
        let subject = SKPinyinSegmentationCandidates(resources: resources, configuration: config)!
        var checks: [[String: Any]] = [], queries: [String] = []
        func check(_ label: String, _ passed: Bool) { checks.append(["label": label, "passed": passed]) }
        func native(_ input: String = "shuna") -> SKEngineState {
            SKEngineState(input: input, preedit: input, candidates: [SKCandidate(index: 0, text: "书拿", comment: "shu na"), SKCandidate(index: 1, text: "书", comment: "shu")])
        }
        func query(_ text: String) -> (String) -> SKEngineState {
            { path in
                queries.append(path)
                return SKEngineState(input: path, candidates: [SKCandidate(index: 0, text: text, comment: path.replacingOccurrences(of: "'", with: " "))])
            }
        }
        func present(_ state: SKEngineState, text: String) -> SKEngineState { subject.present(state, query: query(text)) }
        let initial = present(native(), text: "顺啊")
        check("first presentation queries alternative once", queries == ["shun'a"])
        check("native first choice remains first", initial.candidates.first?.text == "书拿")
        check("alternative is ahead of native partial prefix", initial.candidates.map(\.text) == ["书拿", "顺啊", "书"])
        check("selection maps exact code and text", subject.selection(at: -100)?.code == "shun'a" && subject.selection(at: -100)?.text == "顺啊")
        queries = []
        let reranked = present(native(), text: "舜啊")
        check("cache hit still queries native again", queries == ["shun'a"])
        check("cache hit exposes new native rank", reranked.candidates.contains { $0.text == "舜啊" } && !reranked.candidates.contains { $0.text == "顺啊" })
        check("selection route refreshed for new rank", subject.selection(at: -100)?.text == "舜啊")
        queries = []
        let empty = subject.present(native()) { path in queries.append(path); return SKEngineState(input: path) }
        check("empty query output has no stale candidate", empty.candidates == native().candidates)
        check("empty query output clears stale route", subject.selection(at: -100) == nil)
        let recovered = present(native(), text: "顺啊")
        check("empty native result never negatively cached", queries == ["shun'a", "shun'a"] && recovered.candidates.contains { $0.text == "顺啊" })
        queries = []
        var represented = native(); represented.candidates.append(SKCandidate(index: 2, text: "顺啊", comment: "shun a"))
        let representedResult = present(represented, text: "不应出现")
        check("existing parse paths rechecked on cache hit", queries.isEmpty && representedResult.candidates == represented.candidates)
        check("native representation clears synthetic route", subject.selection(at: -100) == nil)
        var otherNative = native(); otherNative.candidates = [SKCandidate(index: 0, text: "顺啊", comment: "shun a")]
        _ = present(otherNative, text: "书拿")
        check("changed native paths produce different probe", queries == ["shu'na"])
        check("changed path selection route rebuilt", subject.selection(at: -100)?.code == "shu'na")
        queries = []
        let duplicate = present(native(), text: "书拿")
        check("native text duplicate still deduplicated", duplicate.candidates == native().candidates && queries == ["shun'a"])
        check("duplicate output cannot retain prior route", subject.selection(at: -100) == nil)
        queries = []
        let mismatched = subject.present(native()) { _ in SKEngineState(candidates: [SKCandidate(index: 0, text: "错误路径", comment: "shu n a")]) }
        check("native parse mismatch still rejected", mismatched.candidates == native().candidates && subject.selection(at: -100) == nil)
        var partial = native(); partial.preedit = "书na"
        var nextPage = native(); nextPage.page = 1
        var committed = native(); committed.committedText = "书拿"
        let invalid: [(String, SKEngineState)] = [
            ("partial selection", partial), ("next page", nextPage), ("committed state", committed), ("clear", SKEngineState()),
            ("short input", SKEngineState(input: "xi")), ("uppercase", SKEngineState(input: "SHUNA")),
            ("explicit delimiter", SKEngineState(input: "shu'na")), ("nonASCII", SKEngineState(input: "shun啊")),
            ("overlong input", SKEngineState(input: String(repeating: "a", count: 33)))
        ]
        for (label, state) in invalid {
            _ = present(native(), text: "顺啊"); queries = []
            let result = present(state, text: "不应出现")
            check("\(label) makes no native query", queries.isEmpty)
            check("\(label) clears stale selection", subject.selection(at: -100) == nil)
            check("\(label) preserves input/preedit/candidates/commit", result.input == state.input && result.preedit == state.preedit && result.candidates == state.candidates && result.committedText == state.committedText)
        }
        // Introspection checks bounded ownership without adding production test APIs.
        func cache(_ instance: SKPinyinSegmentationCandidates) -> [String: [String]] {
            Mirror(reflecting: instance).children.first { $0.label == "pathCache" }?.value as? [String: [String]] ?? [:]
        }
        let bounded = SKPinyinSegmentationCandidates(resources: resources, configuration: config)!
        let before = bounded.present(native(), query: query("顺啊"))
        let codes = ["nihao", "shijie", "zhongguo", "jintian", "mingtian", "tianqi", "women", "nimen", "tamen", "shanghai", "beijing", "tianjin", "nanjing", "chongqing", "chengdu", "xian", "xiamen", "hangzhou", "suzhou", "wuhan", "changsha", "kunming", "guangzhou", "shenzhen", "haikou", "fuzhou", "nanchang", "hefei", "zhengzhou", "jinan", "taiyuan", "shijiazhuang", "changchun", "shenyang"]
        for code in codes { _ = bounded.present(SKEngineState(input: code), query: query("候选")) }
        check("cache bounded to 32 input keys", cache(bounded).count == 32)
        check("oldest input evicted after more than 32 distinct codes", cache(bounded)["shuna"] == nil)
        let after = bounded.present(native(), query: query("顺啊"))
        check("recomputed path after eviction preserves full output", before.candidates == after.candidates)
        check("eviction and replay preserve selection route", bounded.selection(at: -100)?.code == "shun'a" && bounded.selection(at: -100)?.text == "顺啊")
        check("replayed input retained within capacity", cache(bounded).count == 32 && cache(bounded)["shuna"] != nil)
        var double = config; double = SKInputConfiguration(schemaID: "shika_flypy", inputPolicy: .chineseRomanization, spelling: .doublePinyin)
        check("double-pinyin remains excluded", SKPinyinSegmentationCandidates(resources: resources, configuration: double) == nil)
        let failed = checks.filter { $0["passed"] as? Bool != true }
        try JSONSerialization.data(withJSONObject: ["checks": checks, "passed": checks.count - failed.count, "failed": failed.count, "scope": "Independent native-query spies and route/capacity invariants; not real ranking accuracy"], options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: args[2]))
        print("\(checks.count - failed.count)/\(checks.count) passed")
        if !failed.isEmpty { exit(1) }
    }
}

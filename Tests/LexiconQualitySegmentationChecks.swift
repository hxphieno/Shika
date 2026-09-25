// Read-only native candidate exploration. Explicit apostrophes are controls,
// not silently counted as successful unseparated-input segmentation.
import Foundation

@main
struct LexiconQualitySegmentationChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let engine = try SKRimeEngine(configuration: SKChineseJapaneseScheme.configuration,
            resourceURL: URL(fileURLWithPath: args[1]), userURL: URL(fileURLWithPath: args[2]))
        var rows: [[String: Any]] = []
        for input in ["piao", "pi'ao", "shuna", "shu'na", "shun'a", "fangan", "dangan", "jiang", "qie", "xian"] {
            _ = engine.clear(); var state = SKEngineState()
            for key in input.utf8 { state = engine.process(key: Int32(key)) }
            var candidates: [SKCandidate] = []
            var next = 0
            var hasMore = true
            while hasMore && next < 512 {
                let page = engine.candidatePage(startingAt: next, limit: 64)
                candidates += page.candidates
                hasMore = page.hasMore && page.nextIndex > next
                next = page.nextIndex
            }
            rows.append(["input": input, "preedit": state.preedit, "displayedCandidates": state.candidates.map { ["index": $0.index, "text": $0.text, "comment": $0.comment] as [String: Any] }, "nativeCandidates": candidates.map { ["index": $0.index, "text": $0.text, "comment": $0.comment] as [String: Any] }, "hasMore": hasMore, "count": candidates.count,
                "furCoatRank": candidates.firstIndex(where: { $0.text == "皮袄" }).map { $0+1 } ?? 0,
                "floatRank": candidates.firstIndex(where: { $0.text == "飘" }).map { $0+1 } ?? 0])
        }
        var checks: [[String: Any]] = []
        func check(_ label: String, _ passed: Bool, _ detail: String = "") { checks.append(["label": label, "passed": passed, "detail": detail]) }
        _ = engine.clear()
        var state = SKEngineState()
        for key in "shuna".utf8 { state = engine.process(key: Int32(key)) }
        if let alternate = state.candidates.first(where: { $0.text == "顺啊" }) {
            let selected = engine.selectCandidate(at: alternate.index)
            check("alternative full parse commits exactly", selected.committedText == "顺啊" && selected.input.isEmpty && selected.candidates.isEmpty)
            check("repeat commit emits no duplicate", engine.commit().committedText.isEmpty)
        } else { check("shuna exposes shun a full parse", false) }
        _ = try engine.selectConfiguration(SKShuangpinScheme.configuration)
        for key in "sihx".utf8 { state = engine.process(key: Int32(key)) }
        check("double pinyin has no full-pinyin segmentation routes", !state.candidates.contains(where: { $0.index <= -100 && $0.index > -1000 }))
        check("double pinyin still offers silk-smooth", state.candidates.first?.text == "丝滑")
        if let top = state.candidates.first {
            let selected = engine.selectCandidate(at: top.index)
            check("double pinyin selection stays exact", selected.committedText == top.text && selected.input.isEmpty)
        }
        let mixed = try SKConversionEngine(configuration: SKChineseJapaneseScheme.configuration(for: .mixed), resourceURL: URL(fileURLWithPath: args[1]), userURL: URL(fileURLWithPath: args[2]))
        var output = ""
        let session = SKInputSession(engine: mixed, configuration: SKChineseJapaneseScheme.configuration(for: .mixed), insertText: { output += $0 }, deleteText: {})
        for key in "shuna" { session.type(String(key)) }
        session.loadMoreCandidates()
        if let alternate = session.state.candidates.first(where: { $0.text == "顺啊" }) {
            session.select(alternate)
            check("mixed expanded alternate routes and clears", output == "顺啊" && session.state.input.isEmpty)
            session.select(alternate)
            check("stale UI selection never repeats commit", output == "顺啊")
        } else { check("mixed preserves alternate parse", false) }
        try JSONSerialization.data(withJSONObject: ["rankingTraining": false, "checks": checks, "limit": 512, "results": rows], options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: args[3]))
    }
}

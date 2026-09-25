import Foundation

/// Run the same checks in separate fresh processes against frozen production
/// and the temporary full-pinyin homophone generalization. Compare native exact
/// candidate sequences independently of added correction candidates.
@main struct FullPinyinGeneralizationChecks {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 4 else { fatalError("resources freshUser report.json") }
        let args = CommandLine.arguments
        let resources = URL(fileURLWithPath: args[1]), user = URL(fileURLWithPath: args[2])
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let config = SKInputScheme.chineseJapanese.configuration
        let engine = try SKRimeEngine(configuration: config, resourceURL: resources, userURL: user)
        var output = "", marked = "", deletes = 0, inserts: [String] = []
        let session = SKInputSession(engine: engine, configuration: config,
            insertText: { output += $0; inserts.append($0) },
            deleteText: { deletes += 1; if !output.isEmpty { output.removeLast() } },
            updateComposition: { marked = $0 })
        var checks: [[String: Any]] = [], snapshots: [[String: Any]] = [], extraRoutes: [[String: Any]] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            checks.append(["name": name, "passed": ok, "detail": detail]); print("\(ok ? "PASS" : "FAIL") \(name) \(detail)")
        }
        func type(_ s: String) { for c in s { session.type(String(c)) } }
        func reset(_ s: String = "") { session.cancel(); output = ""; inserts = []; deletes = 0; type(s) }
        func clear() -> Bool { session.state.input.isEmpty && session.state.candidates.isEmpty && marked.isEmpty }
        func pick(_ text: String) -> Bool {
            for _ in 0..<25 {
                if let c = session.state.candidates.first(where: { $0.text == text }) { session.select(c); return true }
                if session.state.isLastPage { break }; session.loadMoreCandidates()
            }
            return false
        }
        func normalize(_ s: String) -> String {
            s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "nue", with: "nve").replacingOccurrences(of: "lue", with: "lve")
        }
        // No selections occur until every comparison snapshot has been read.
        for raw in ["nihao", "shishi", "quanyi", "quanli", "jingli", "xingshi", "shiyan", "yiyi", "jiezhi", "fanying", "bianzhi", "pinwei", "jiaodai", "zhongsheng", "xi'an", "xian", "lve", "nue", "shanghai", "nihaoshijie", "shanghaijiaotongdaxue", "nohao", "nihoa", "zhongguoo"] {
            reset(raw)
            let exact = session.state.candidates.filter { $0.index >= 0 && normalize($0.comment) == normalize(raw) }
            snapshots.append(["input": raw, "first": session.state.candidates.first?.text ?? "",
                              "nativeExact": exact.map { ["text": $0.text, "index": $0.index, "comment": $0.comment] as [String: Any] },
                              "all": session.state.candidates.map { ["text": $0.text, "index": $0.index, "comment": $0.comment] as [String: Any] }])
            check("snapshot input retains all original keys without commit: \(raw)", output.isEmpty && session.state.input == raw)
        }
        for raw in ["nihao", "nohao", "nihoa", "zhongguoo", "shanghaijiaotongdaxue"] {
            reset(raw); session.type("\n")
            check("full-pinyin Return confirms exact raw input: \(raw)", output == raw && clear() && inserts == [raw])
            session.type("\n"); check("second Return reaches host once: \(raw)", output == raw + "\n")
        }
        for (raw, target) in [("nohao", "你好"), ("nihoa", "你好"), ("zhongguoo", "中国")] {
            reset(raw); let selected = pick(target)
            check("existing correction consumes full input: \(raw)", selected && output == target && clear(), "output=\(output)")
            session.commitPending(); check("existing correction is committed only once: \(raw)", output == target)
        }
        for end in [" ", "\n", "，", "switch"] {
            reset("nihaoshijie"); let selected = pick("你好")
            check("partial Chinese selection remains marked: \(end.debugDescription)", selected && output.isEmpty && marked.hasPrefix("你好"))
            if end == "switch" { try session.switchConfiguration(to: SKInputScheme.shuangpin.configuration) }
            else { session.type(end) }
            let expected = end == "\n" ? "你好shijie" : "你好世界" + (end == "，" ? "，" : "")
            check("partial Chinese tail survives confirmation: \(end.debugDescription)", output == expected && clear(), "output=\(output)")
            if end == "switch" { try session.switchConfiguration(to: config) }
        }
        reset("nihaoshijie"); let partial = pick("你好"); session.deleteBackward()
        check("partial undo preserves all original pinyin", partial && session.state.input == "nihaoshijie" && output.isEmpty && deletes == 0)
        session.type("\n"); check("Return after partial undo preserves exact original input", output == "nihaoshijie" && clear())
        reset("nihoa")
        var deleted = true
        for count in stride(from: 4, through: 0, by: -1) {
            session.deleteBackward(); deleted = deleted && session.state.input == String("nihoa".prefix(count)) && output.isEmpty && deletes == 0
        }
        check("ordinary delete edits the actual mistyped raw code", deleted && clear())
        session.deleteBackward(); check("idle delete alone reaches host", deletes == 1)
        for literal in ["，", "1", "A", "🦌"] {
            reset("nihao"); session.type(literal); check("literal follows a single committed Chinese word: \(literal)", output == "你好" + literal && clear())
        }
        reset("ni"); let first = session.state.candidates; let originalMarked = marked
        session.loadMoreCandidates()
        check("candidate expansion keeps marked text and unique IDs", marked == originalMarked && output.isEmpty && Set(session.state.candidates.map(\.index)).count == session.state.candidates.count)
        if let later = session.state.candidates.first(where: { !first.contains($0) }) {
            session.select(later); check("expanded native candidate selects correct displayed text", output == later.text && clear())
        } else { check("expanded native candidate exists", false) }
        reset("nohao"); let stale = session.state.candidates.first; session.cancel()
        if let stale { session.select(stale) }
        check("cancelled correction cannot commit through a stale item", output.isEmpty && clear())
        for raw in ["nohao", "nihoa", "zhongguoo"] {
            reset(raw)
            if let extra = session.state.candidates.first(where: { (-5 ... -4).contains($0.index) }) {
                session.select(extra)
                extraRoutes.append(["input": raw, "text": extra.text, "index": extra.index])
                check("new same-code alternative has a complete native selection route: \(raw)", output == extra.text && clear(), "target=\(extra.text), output=\(output)")
                session.commitPending()
                check("new same-code alternative is never replayed", output == extra.text)
            }
        }
        check("full-pinyin actions never create the double-pinyin index", !FileManager.default.fileExists(atPath: user.appendingPathComponent("double-pinyin-spelling.json").path))
        let failures = checks.filter { !($0["passed"] as! Bool) }.count
        let report: [String: Any] = ["environment": "macOS native real Rime/input session; no UI", "checkCount": checks.count,
                                   "failures": failures, "checks": checks, "snapshots": snapshots, "extraRouteSelections": extraRoutes]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[3]))
        print("\(failures == 0 ? "PASS" : "FAIL") \(checks.count - failures)/\(checks.count)")
        if failures > 0 { exit(1) }
    }
}

// Independent coverage/paging/commit acceptance. No production changes or UI mocks.
import Foundation
import CoreText

@MainActor private final class GlyphPagingEngine: SKInputEngine {
    var rows: [SKCandidate]
    var input = ""
    var pageCalls = 0
    var calls: [String] = []
    var selected: [Int] = []
    let initialCount: Int
    init(rows: [SKCandidate], initialCount: Int = 4) { self.rows = rows; self.initialCount = initialCount }
    func snapshot() -> SKEngineState {
        SKEngineState(input: input, preedit: input, candidates: input.isEmpty ? [] : Array(rows.prefix(initialCount)), isLastPage: rows.count <= initialCount)
    }
    func process(key: Int32) -> SKEngineState {
        calls.append("key:\(key)")
        if key == 0xff0d { let raw = input; _ = clear(); return SKEngineState(committedText: raw) }
        if key == 32 { return commit() }
        if key == 0xff08 { input = String(input.dropLast()); return snapshot() }
        input += String(UnicodeScalar(UInt32(key))!); return snapshot()
    }
    func selectCandidate(at index: Int) -> SKEngineState {
        calls.append("select:\(index)"); selected.append(index)
        let text = rows.first { $0.index == index }?.text ?? ""
        _ = clear(); return SKEngineState(committedText: text)
    }
    func candidatePage(startingAt index: Int, limit: Int) -> SKCandidatePage {
        pageCalls += 1
        let end = min(rows.count, index + limit)
        return SKCandidatePage(candidates: index < rows.count ? Array(rows[index..<end]) : [], nextIndex: end, hasMore: end < rows.count)
    }
    func changePage(backward: Bool) -> SKEngineState { calls.append("page:\(backward)"); return snapshot() }
    func commit() -> SKEngineState { calls.append("commit"); return selectCandidate(at: rows.first?.index ?? 0) }
    func clear() -> SKEngineState { input = ""; return SKEngineState() }
    func selectConfiguration(_ configuration: SKInputConfiguration) throws -> SKEngineState { calls.append("configuration"); return clear() }
}

@main struct CandidateGlyphIndependentChecks {
    @MainActor static func main() async throws {
        let a = CommandLine.arguments
        let resources = URL(fileURLWithPath: a[1]), root = URL(fileURLWithPath: a[2])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var checks: [[String: Any]] = [], fontRows: [[String: Any]] = []
        func check(_ label: String, _ value: Bool, _ detail: String = "") { checks.append(["label": label, "passed": value, "detail": detail]) }
        let coverage = SKCandidateGlyphCoverage()
        let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[3]))) as! [[String: String]]
        let font = CTFontCreateUIFontForLanguage(.system, 20, nil)!
        for item in cases {
            let text = item["text"]!, id = item["id"]!
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            let names = runs.map { CTFontCopyPostScriptName((CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as! CTFont) as String }
            let lastResort = zip(runs, names).contains { run, name in
                name.lowercased().contains("lastresort") && !CTRunGetImageBounds(run, nil, CFRange(location: 0, length: 0)).isEmpty
            }
            let displayable = coverage.canDisplay(text)
            check("\(id): shaped fallback agrees with gate", displayable == !lastResort)
            if item["expect"] == "preserve-normal-display" { check("\(id): ordinary display preserved", displayable, names.joined(separator: ",")) }
            fontRows.append(["id": id, "textUTF8": Array(text.utf8), "text": text, "fonts": names, "runInkBounds": runs.map { String(describing: CTRunGetImageBounds($0, nil, CFRange(location: 0, length: 0))) }, "displayable": displayable])
        }
        func cache() -> [Data: Bool] { Mirror(reflecting: coverage).children.first { $0.label == "cache" }?.value as? [Data: Bool] ?? [:] }
        _ = coverage.canDisplay("ば"); _ = coverage.canDisplay("は\u{3099}")
        check("canonically equivalent input has distinct byte cache keys", cache()[Data("ば".utf8)] != nil && cache()[Data("は\u{3099}".utf8)] != nil)
        let overlong = String(repeating: "a", count: 513)
        check("long supported text remains displayable", coverage.canDisplay(overlong))
        check("over-512-byte text is not retained", cache()[Data(overlong.utf8)] == nil)
        for index in 0..<520 { _ = coverage.canDisplay("普通文本\(index)") }
        check("font decision cache at most 512 entries", cache().count == 512)
        check("all retained cache keys at most 512 bytes", cache().keys.allSatisfy { $0.count <= 512 })
        check("evicted NFC and NFD rerender safely", coverage.canDisplay("ば") && coverage.canDisplay("は\u{3099}"))
        let config = SKChineseJapaneseScheme.configuration
        func rows(_ count: Int, visibleFrom: Int = 0) -> [SKCandidate] {
            (0..<count).map { SKCandidate(index: $0, text: $0 < visibleFrom ? "隐藏\($0)" : "可见\($0)", comment: "原注释", consumedInputCount: $0 % 2 == 0 ? 1 : 2) }
        }
        let gate: (String) -> Bool = { !$0.hasPrefix("隐藏") }
        // Entirely visible: preserve engine's native dispatch, IDs and metadata.
        let allEngine = GlyphPagingEngine(rows: rows(12)); var allOutput = ""
        let allSession = SKInputSession(engine: allEngine, configuration: config, candidateIsDisplayable: gate, insertText: { allOutput += $0 }, deleteText: {})
        allSession.type("a")
        check("all-visible initial candidate records unchanged", allSession.state.candidates == Array(allEngine.rows.prefix(4)))
        allSession.loadMoreCandidates()
        check("all-visible pagination preserves all candidate records", allSession.state.candidates == allEngine.rows)
        allSession.type(" ")
        check("all-visible space retains native key dispatch", allEngine.calls.contains("key:32") && allOutput == "可见0")
        allSession.type("b"); allSession.commitPending()
        check("all-visible flush retains native commit", allEngine.calls.filter { $0 == "commit" }.count == 2)
        let hiddenEngine = GlyphPagingEngine(rows: rows(12, visibleFrom: 3)); var output = ""
        let session = SKInputSession(engine: hiddenEngine, configuration: config, candidateIsDisplayable: gate, insertText: { output += $0 }, deleteText: {})
        session.type("a")
        check("filter preserves surviving IDs and consumed counts", session.state.candidates == Array(hiddenEngine.rows[3..<7]))
        let staleHidden = hiddenEngine.rows[0]; session.select(staleHidden)
        check("hidden stale candidate cannot be manually selected", hiddenEngine.selected.isEmpty)
        session.type(" ")
        check("space selects first visible original ID", hiddenEngine.selected == [3] && output == "可见3" && !hiddenEngine.calls.contains("key:32"))
        output = ""; session.type("a"); session.type("\n")
        check("Return commits original letters despite hidden first", output == "a" && session.state.input.isEmpty)
        let lateEngine = GlyphPagingEngine(rows: rows(230, visibleFrom: 220)); var lateOutput = ""
        let late = SKInputSession(engine: lateEngine, configuration: config, candidateIsDisplayable: gate, insertText: { lateOutput += $0 }, deleteText: {})
        late.type("a")
        check("initial hidden scan bounded to four page calls", lateEngine.pageCalls <= 4)
        for _ in 0..<1000 where late.state.candidates.isEmpty { await Task.yield() }
        check("valid candidates after long hidden run remain reachable", late.state.candidates.first?.index == 220)
        check("late pagination never commits or changes raw input", lateOutput.isEmpty && late.state.input == "a")
        late.loadMoreCandidates()
        for _ in 0..<1000 where !late.state.isLastPage { await Task.yield() }
        check("late pagination reaches true end and retains IDs", late.state.isLastPage && late.state.candidates.map(\.index) == Array(220..<230))
        let cancelEngine = GlyphPagingEngine(rows: rows(230, visibleFrom: 220))
        let cancelled = SKInputSession(engine: cancelEngine, configuration: config, candidateIsDisplayable: gate, insertText: { _ in }, deleteText: {})
        cancelled.type("a"); cancelled.cancel(); let afterCancel = cancelEngine.pageCalls
        for _ in 0..<100 { await Task.yield() }
        check("cancelled continuation cannot refill old input", cancelled.state.input.isEmpty && cancelled.state.candidates.isEmpty && cancelEngine.pageCalls == afterCancel)
        let editedEngine = GlyphPagingEngine(rows: rows(230, visibleFrom: 220))
        let edited = SKInputSession(engine: editedEngine, configuration: config, candidateIsDisplayable: gate, insertText: { _ in }, deleteText: {})
        edited.type("a"); editedEngine.rows = rows(4); edited.type("b")
        for _ in 0..<100 { await Task.yield() }
        check("new input cancels old candidate continuation", edited.state.input == "ab" && edited.state.candidates == editedEngine.rows)
        // Same visible text with distinct consumption must survive expansion.
        let repeated = [SKCandidate(index: 0, text: "相同", comment: "完整", consumedInputCount: 2), SKCandidate(index: 1, text: "相同", comment: "前缀", consumedInputCount: 1)]
        let repeatEngine = GlyphPagingEngine(rows: repeated, initialCount: 1)
        let repeatSession = SKInputSession(engine: repeatEngine, configuration: config, candidateIsDisplayable: gate, insertText: { _ in }, deleteText: {})
        repeatSession.type("a"); repeatSession.loadMoreCandidates()
        check("same text with distinct consumed lengths not merged", repeatSession.state.candidates == repeated)
        // True mixed partial paths: space preserves tail, punctuation flushes it.
        let mixedUser = root.appendingPathComponent("mixed-user")
        let mixed = try SKMixedEngine(resources: resources, userDirectory: mixedUser)
        let mixedConfig = SKChineseJapaneseScheme.configuration(for: .mixed)
        var mixedOutput = ""
        let mixedSession = SKInputSession(engine: mixed, configuration: mixedConfig, candidateIsDisplayable: { $0 == "今天也" }, insertText: { mixedOutput += $0 }, deleteText: {})
        let raw = "jintianyearigatouq"
        for c in raw { mixedSession.type(String(c)) }
        for _ in 0..<1000 where mixedSession.state.candidates.isEmpty && !mixedSession.state.isLastPage { await Task.yield() }
        check("real mixed visible partial candidate exists", mixedSession.state.candidates.first?.text == "今天也")
        let learning = mixedUser.appendingPathComponent("mixed-learning.json")
        check("filtered browsing does not create mixed learning", !FileManager.default.fileExists(atPath: learning.path))
        mixedSession.type(" ")
        check("space partial selection retains pending tail", mixedOutput.isEmpty && mixedSession.state.preedit == "今天也arigatouq" && mixedSession.state.input == raw)
        check("partial selection alone does not train mixed learning", !FileManager.default.fileExists(atPath: learning.path))
        mixedSession.type("，")
        check("all-hidden tail flush retains previously selected mixed prefix", mixedOutput == "今天也arigatouq，" && mixedSession.state.input.isEmpty, mixedOutput)
        check("all-hidden tail fallback does not train learning", !FileManager.default.fileExists(atPath: learning.path))
        mixedOutput = ""
        mixedSession.cancel(); for c in raw { mixedSession.type(String(c)) }
        for _ in 0..<1000 where mixedSession.state.candidates.isEmpty && !mixedSession.state.isLastPage { await Task.yield() }
        mixedSession.type("，")
        check("punctuation flush of visible partial preserves raw tail", mixedOutput == "今天也arigatouq，" && mixedSession.state.input.isEmpty)
        check("raw-tail mixed flush does not train nonexistent full phrase", !FileManager.default.fileExists(atPath: learning.path))
        // Native Rime owns the confirmed-prefix/raw-tail boundary as well.
        let rime = try SKRimeEngine(configuration: SKShuangpinScheme.configuration, resourceURL: resources, userURL: mixedUser)
        var allowRime = true, rimeOutput = ""
        let rimeSession = SKInputSession(engine: rime, configuration: SKShuangpinScheme.configuration, candidateIsDisplayable: { _ in allowRime }, insertText: { rimeOutput += $0 }, deleteText: {})
        var rimePartialObservations: [[String: String]] = []
        for (ending, expected) in [(" ", "颠簸dnbo"), ("，", "颠簸dnbo，"), ("\n", "颠簸dnbo")] {
            allowRime = true; rimeOutput = ""; rimeSession.cancel()
            for c in "dmbodnbo" { rimeSession.type(String(c)) }
            if let prefix = rimeSession.state.candidates.first(where: { $0.text == "颠簸" }) {
                allowRime = false; rimeSession.select(prefix)
                let confirmedPreedit = rimeSession.state.preedit, confirmedRaw = rimeSession.state.input
                for _ in 0..<1000 where !rimeSession.state.isLastPage { await Task.yield() }
                rimeSession.type(ending)
                check("Rime confirmed prefix survives hidden-tail ending \(ending.debugDescription)", rimeOutput == expected && rimeSession.state.input.isEmpty, rimeOutput)
                rimePartialObservations.append(["ending": ending, "rawAfterPrefix": confirmedRaw, "preeditAfterPrefix": confirmedPreedit, "output": rimeOutput])
            } else { check("Rime partial prefix available for \(ending.debugDescription)", false) }
        }
        var visiblePrefixOutput = ""
        let prefixFlush = SKInputSession(engine: rime, configuration: SKShuangpinScheme.configuration,
            candidateIsDisplayable: { $0 == "颠簸" }, insertText: { visiblePrefixOutput += $0 }, deleteText: {})
        prefixFlush.cancel()
        for c in "dmbodnbo" { prefixFlush.type(String(c)) }
        for _ in 0..<1000 where !prefixFlush.state.isLastPage { await Task.yield() }
        let visiblePrefixBefore = prefixFlush.state.candidates.first?.text
        prefixFlush.type("，")
        check("Rime automatic visible-prefix flush cannot select unchecked tail", visiblePrefixBefore == "颠簸" && visiblePrefixOutput == "颠簸dnbo，" && prefixFlush.state.input.isEmpty, visiblePrefixOutput)
        let failed = checks.filter { $0["passed"] as? Bool != true }
        let result: [String: Any] = ["checks": checks, "passed": checks.count-failed.count, "failed": failed.count, "fontProbes": fontRows, "rimePartialObservations": rimePartialObservations, "platform": "macOS; font availability is device-specific", "scope": "Independent font boundary, session paging spies and real mixed partial selection"]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: root.appendingPathComponent("independent.json"))
        print("\(checks.count-failed.count)/\(checks.count) passed")
        for item in failed { print(item) }
        if !failed.isEmpty { exit(1) }
    }
}

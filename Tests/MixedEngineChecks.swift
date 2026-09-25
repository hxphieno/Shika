import Foundation
import Darwin

struct MixedCase: Decodable {
    let id: String
    let input: String
    let expected: [String]
    let category: String
    let sourceIDs: [String]
    let provenance: String
    let split: String
}
struct MixedCorpus: Decodable { let cases: [MixedCase] }
@main struct MixedEngineChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 6 else { fatalError("resources user cases output baseline|16|32|64 [probe input ...]") }
        let resources = URL(fileURLWithPath: args[1]), user = URL(fileURLWithPath: args[2])
        let configuration = SKChineseJapaneseScheme.configuration(for: .mixed)
        let engine: any SKInputEngine = args[5] == "baseline"
            ? try SKLegacyMixedEngine(configuration: configuration, resourceURL: resources, userURL: user)
            : try SKMixedEngine(resources: resources, userDirectory: user, beamWidth: Int(args[5]) ?? 32)
        var rows: [[String: Any]] = [], checks: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            checks.append(["name": name, "passed": passed, "detail": detail])
        }
        @MainActor func type(_ input: String) -> SKEngineState {
            _ = engine.clear(); var state = SKEngineState()
            for key in input.utf8 { state = engine.process(key: Int32(key)) }
            return state
        }
        func footprint() -> UInt64 {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? info.phys_footprint : 0
        }
        let corpus = try JSONDecoder().decode(MixedCorpus.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        // Ranking pass makes NO selections and writes NO learning records.
        let requestedSplit = ProcessInfo.processInfo.environment["MIXED_SPLIT"]
        for item in corpus.cases where requestedSplit == nil || item.split == requestedSplit {
            _ = engine.clear(); var durations: [Double] = [], unexpected = ""
            for key in item.input.utf8 {
                let begin = DispatchTime.now().uptimeNanoseconds
                let state = engine.process(key: Int32(key)); unexpected += state.committedText
                durations.append(Double(DispatchTime.now().uptimeNanoseconds - begin) / 1e6)
            }
            var choices: [SKCandidate] = [], next = 0
            for _ in 0..<3 {
                let page = engine.candidatePage(startingAt: next, limit: 64)
                choices += page.candidates; next = page.nextIndex
                if !page.hasMore { break }
            }
            // The legacy merged initial page must be included: its pagination
            // itself only enumerated Chinese. Do not make its baseline worse.
            let initial = engine.changePage(backward: true).candidates
            var seen = Set<SKCandidate.ContentIdentity>()
            choices = (initial + choices).filter { seen.insert($0.contentIdentity).inserted }
            let rank = choices.firstIndex {
                item.expected.contains($0.text) && ($0.consumedInputCount == nil || $0.consumedInputCount == item.input.count)
            }.map { $0 + 1 } ?? 0
            rows.append(["id": item.id, "input": item.input, "expected": item.expected,
                "category": item.category, "split": item.split, "rank": rank,
                "candidates": Array(choices.prefix(10)).map(\.text), "keyMS": durations,
                "footprintBytes": footprint(), "unexpectedCommit": unexpected])
        }
        if args[5] != "baseline" {
            for (raw, prefix, remainder, expected) in [
                ("jintianyearigatou", "今天也", "arigatou", "ありがとう"),
                ("arigatoujintianye", "ありがとう", "jintianye", "今天也"),
                ("zhegesugoiwoxihuan", "这个", "sugoiwoxihuan", "すごい我喜欢")
            ] {
                _ = type(raw)
                var all = engine.candidatePage(startingAt: 0, limit: 64).candidates
                guard let selected = all.first(where: {$0.text == prefix}) else {
                    check("partial prefix available: \(raw)", false, all.map(\.text).joined(separator: "|")); continue
                }
                let after = engine.selectCandidate(at: selected.index)
                check("partial stays marked: \(raw)", after.committedText.isEmpty && after.preedit == prefix + remainder, after.preedit)
                all = engine.candidatePage(startingAt: 0, limit: 64).candidates
                check("remainder top3: \(raw)", all.prefix(3).contains(where: {$0.text == expected}), all.prefix(3).map(\.text).joined(separator: "|"))
                let enter = engine.process(key: 0xff0d)
                check("partial Return preserves selected prefix and raw tail", enter.committedText == prefix + remainder && enter.input.isEmpty, enter.committedText)
                _ = type(raw)
                if let p = engine.candidatePage(startingAt: 0, limit: 64).candidates.first(where: {$0.text == prefix}) {
                    _ = engine.selectCandidate(at: p.index)
                    var state = SKEngineState()
                    for _ in remainder { state = engine.process(key: 0xff08) }
                    check("delete tail retains prefix", state.preedit == prefix, state.preedit)
                    state = engine.process(key: 0xff08)
                    check("delete at prefix boundary restores spelling", !state.input.isEmpty && state.preedit != prefix, state.preedit)
                }
            }
            let before = type("jintianyearigatou")
            let expanded = engine.candidatePage(startingAt: 8, limit: 40)
            check("expanded candidates have stable IDs", Set(expanded.candidates.map(\.index)).count == expanded.candidates.count && expanded.candidates.first?.index == 8)
            let invalid = engine.selectCandidate(at: Int.max)
            check("invalid candidate leaves composition", invalid.input == before.input && invalid.preedit == before.preedit)
            let enter = engine.process(key: 0xff0d)
            check("Return confirms original letters", enter.committedText == "jintianyearigatou" && enter.input.isEmpty)
            check("Return commit one-shot", engine.process(key: 0xff0d).committedText.isEmpty)
            _ = type("jintianyearigatou")
            check("space chooses joint sentence", engine.process(key: 32).committedText == "今天也ありがとう")
            _ = type("jintianyearigatouzzz")
            let flushed = engine.commit()
            check("flush never loses undecoded tail", flushed.input.isEmpty && flushed.committedText.hasSuffix("zzz"), flushed.committedText)
            _ = type(String(repeating: "q", count: 110))
            check("long raw input preserved", engine.process(key: 0xff0d).committedText == String(repeating: "q", count: 110))
            var output = "", marked = ""
            let session = SKInputSession(engine: engine, configuration: configuration, insertText: {output += $0}, deleteText: {}, updateComposition: {marked = $0})
            session.cancel()
            for c in "jintianyearigatou" {session.type(String(c))}
            session.loadMoreCandidates()
            if let prefix = session.state.candidates.first(where: {$0.text == "今天也"}) {
                session.select(prefix)
                check("session partial marked text", output.isEmpty && marked == "今天也arigatou", marked)
                session.type(" ")
                check("session commits mixed sentence once", output == "今天也ありがとう" && marked.isEmpty, output)
            } else {check("session can select prefix after expansion", false)}
            for (config, raw, expected) in [(SKChineseJapaneseScheme.configuration,"nihao","你好"), (SKInputScheme.shuangpin.configuration,"nihc","你好"), (SKChineseJapaneseScheme.configuration(for: .japanese),"arigatou","ありがとう")] {
                try session.switchConfiguration(to: configuration) // direct mixed engine intentionally rejects nonmixed modes
                let pure = try SKConversionEngine(configuration: config, resourceURL: resources, userURL: user)
                var state = SKEngineState()
                for c in raw.utf8 {state = pure.process(key: Int32(c))}
                check("pure mode unchanged: \(raw)", state.candidates.contains(where: {$0.text == expected}))
            }
        }
        let report: [String: Any] = ["mode":args[5], "cases": rows, "checks":checks,
            "failed":checks.filter { !($0["passed"] as! Bool) }.count,
            "platform":"macOS production engines; footprint is not a real iOS extension measurement", "rankingLearning":false]
        try JSONSerialization.data(withJSONObject: report, options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:args[4]))
        print("Mixed \(args[5]): \(rows.count) cases; \(checks.filter { !($0["passed"] as! Bool) }.count)/\(checks.count) behavior failures")
        for row in checks where !(row["passed"] as! Bool) {print(row)}
        if checks.contains(where: { !($0["passed"] as! Bool) }) { exit(1) }
    }
}

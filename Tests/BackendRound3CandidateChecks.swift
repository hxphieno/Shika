import Foundation

/// Independent routing tests: fixed query responses exercise candidate semantics,
/// not native Rime quality. The spy detects redundant work and stale ranking.
@main struct BackendRound3CandidateChecks {
    static func main() throws {
        let args = CommandLine.arguments
        let root = URL(fileURLWithPath: args[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var records = Data(), pool = Data()
        func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        for (code, word, frequency) in [("shijia", "世家", UInt32(900)), ("shijie", "世界", UInt32(1000))] {
            let offset = UInt32(pool.count); pool.append(contentsOf: code.utf8)
            let textOffset = UInt32(pool.count); pool.append(contentsOf: word.utf8)
            append(offset, to: &records); append(UInt16(code.utf8.count), to: &records)
            append(UInt16(word.utf8.count), to: &records); append(textOffset, to: &records); append(frequency, to: &records)
        }
        var bytes = Data("SKC1".utf8); append(UInt32(2), to: &bytes); bytes.append(records); bytes.append(pool)
        try bytes.write(to: root.appendingPathComponent("shika_pinyin.correction.bin"))
        let config = SKInputConfiguration(schemaID: "shika_pinyin", inputPolicy: .chineseRomanization, spelling: .fullPinyin)
        let presenter = SKCorrectionCandidates(resources: root, configuration: config)!
        var checks: [[String: Any]] = [], observations: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool) { checks.append(["name": name, "passed": passed]) }
        func candidate(_ index: Int, _ text: String, _ comment: String) -> SKCandidate { SKCandidate(index: index, text: text, comment: comment) }
        func snapshot(_ input: String, _ candidates: [SKCandidate]) -> SKEngineState { SKEngineState(input: input, preedit: input, candidates: candidates) }
        func signature(_ state: SKEngineState) -> [[String: Any]] {
            state.candidates.map { c in ["index": c.index, "text": c.text, "comment": c.comment,
                "routeCode": presenter.selection(at: c.index)?.code ?? "", "routeText": presenter.selection(at: c.index)?.text ?? ""] }
        }
        let learned = ["诗界", "市界", "石界", "食界"].map { SKLearnedSpellingIndex.Entry(code: "shijie", text: $0) }
        let nativeWords = ["世界", "视界", "师姐", "诗界", "市界", "石界", "食界"]
        let response = snapshot("shijie", nativeWords.enumerated().map { candidate($0.offset, $0.element, "shi jie") })
        let typo = snapshot("shijiee", [candidate(0, "世界", "shi jie"), candidate(1, "诗", "shi")])
        var calls: [String: Int] = [:]
        let repaired = presenter.present(typo, learned: learned) { code in calls[code, default: 0] += 1; return response }
        check("same text partial native route replaced by complete repair", repaired.candidates.filter { $0.text == "世界" }.count == 1 && repaired.candidates.first { $0.text == "世界" }!.index < 0)
        check("all four learned homophones remain visible", learned.allSatisfy { e in repaired.candidates.contains { $0.text == e.text } })
        check("all correction selections retain code and text", repaired.candidates.filter { $0.index < 0 }.allSatisfy { c in presenter.selection(at: c.index)?.code == "shijie" && presenter.selection(at: c.index)?.text == c.text })
        check("unrelated partial candidate retained", repaired.candidates.contains { $0.index == 1 && $0.text == "诗" })
        observations.append(["case": "same-code learned homophones", "queryCounts": calls, "candidates": signature(repaired)])
        if args.contains("--memoized") { check("query each code once per presentation", calls.values.allSatisfy { $0 == 1 }) }

        let exact = snapshot("shijie", [candidate(0, "世界", "shi jie"), candidate(1, "视界", "shi jie"), candidate(2, "师姐", "shi jie"), candidate(3, "世", "shi")])
        let protected = presenter.present(exact) { _ in snapshot("shijia", [candidate(0, "世家", "shi jia")]) }
        check("all leading exact homophones retain order", Array(protected.candidates.prefix(3)) == Array(exact.candidates.prefix(3)))
        check("near spelling follows complete exact candidates", protected.candidates.firstIndex { $0.text == "世家" } == 3)
        observations.append(["case": "exact protection", "candidates": signature(protected)])

        var queryVersion = 0
        let original = presenter.present(typo) { _ in queryVersion += 1; return snapshot("shijie", [candidate(0, "世界", "shi jie")]) }
        let changed = presenter.present(typo) { _ in queryVersion += 1; return snapshot("shijie", [candidate(0, "视界", "shi jie")]) }
        check("next event rereads changed native ranking", original.candidates.first?.text == "世界" && changed.candidates.first?.text == "视界" && queryVersion == 2)
        observations.append(["case": "next event new rank", "candidates": signature(changed)])
        let rejected = presenter.present(typo, learned: [SKLearnedSpellingIndex.Entry(code: "shijie", text: "假词")]) { _ in response }
        check("unverified learned text never inserted", !rejected.candidates.contains { $0.text == "假词" })
        let wrongReading = presenter.present(typo, learned: learned) { _ in snapshot("shijie", [candidate(0, "诗界", "shi jia")]) }
        check("native text with wrong spelling cannot verify correction", !wrongReading.candidates.contains { $0.index < 0 })
        for (name, state) in [
            ("empty", SKEngineState()),
            ("paged", SKEngineState(input: "shijiee", preedit: "shijiee", candidates: typo.candidates, page: 1)),
            ("committed", SKEngineState(input: "shijiee", preedit: "shijiee", candidates: typo.candidates, committedText: "世")),
            ("partial selection", SKEngineState(input: "shijiee", preedit: "世jiee", candidates: typo.candidates))
        ] {
            var count = 0
            let result = presenter.present(state, learned: learned) { _ in count += 1; return response }
            check("\(name) bypasses corrections without query", count == 0 && result.candidates == state.candidates)
            check("\(name) invalidates old selection routes", presenter.selection(at: -1) == nil && presenter.selection(at: -1000) == nil)
        }
        let failed = checks.filter { !($0["passed"] as! Bool) }
        let report: [String: Any] = ["checks": checks, "observations": observations, "passed": checks.count-failed.count, "failed": failed.count,
            "scope": "Independent deterministic candidate-routing unit tests; query spy, not real Rime quality"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[2]))
        print("candidate checks \(checks.count-failed.count)/\(checks.count)")
        if !failed.isEmpty { exit(1) }
    }
}

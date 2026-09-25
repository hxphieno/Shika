import Foundation
import Darwin

@main struct ShuangpinOptimizationChecks {
    struct Case: Decodable {
        let schema: String, kind: String, input: String, target: String, correct: String, split: String
        let id: String?
    }
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 6 else { fatalError("runner resources user cases.json output.json split|all [commit-id]") }
        let resources = URL(fileURLWithPath: args[1]), user = URL(fileURLWithPath: args[2])
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let split = args.count > 5 ? args[5] : "all"
        let commitID = args.count > 6 ? args[6] : ""
        let mapping = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: resources.appendingPathComponent("correction-syllables.json")))
        let start = CFAbsoluteTimeGetCurrent()
        let engine = try SKRimeEngine(configuration: SKInputScheme.shuangpin.configuration, resourceURL: resources, userURL: user)
        let startupMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
        var schema = "shika_flypy", rows: [[String: Any]] = [], timings: [Double] = []
        for (offset, item) in cases.enumerated() where (split == "all" || item.split == split) && (commitID.isEmpty || item.id == commitID) {
            _ = engine.clear()
            let config = SKInputScheme(schemaID: item.schema)!.configuration
            if schema != item.schema { _ = try engine.selectConfiguration(config); schema = item.schema }
            var state = SKEngineState(), unexpected = "", keyTimes: [Double] = []
            for key in item.input.utf8 {
                let start = CFAbsoluteTimeGetCurrent()
                state = engine.process(key: Int32(key))
                keyTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                unexpected += state.committedText
            }
            func complete(_ c: SKCandidate) -> Bool {
                if let consumed = c.consumedInputCount { return consumed == state.input.utf8.count }
                return c.index < 0 || config.spelling.isExact(comment: c.comment, input: state.input, syllables: mapping)
            }
            let target = state.candidates.first(where: { $0.text == item.target && complete($0) })
            var row: [String: Any] = ["id": item.id ?? "legacy-\(offset)", "schema": item.schema, "kind": item.kind,
                "split": item.split, "input": item.input, "target": item.target, "correct": item.correct,
                "rank": state.candidates.firstIndex(where: { $0.text == item.target && complete($0) }).map { $0 + 1 } ?? 0,
                "textOnlyRank": state.candidates.firstIndex(where: { $0.text == item.target }).map { $0 + 1 } ?? 0,
                "candidates": state.candidates.map { ["text": $0.text, "index": $0.index, "comment": $0.comment, "complete": complete($0)] as [String: Any] },
                "unexpectedCommit": unexpected, "keyTimesMS": keyTimes]
            // Only explicit isolated replay processes select an answer.
            if !commitID.isEmpty, let choice = target {
                let selected = engine.selectCandidate(at: choice.index)
                row["commit"] = selected.committedText
                row["remaining"] = selected.input
                row["remainingPreedit"] = selected.preedit
                row["remainingCandidates"] = selected.candidates.count
                let repeated = engine.commit()
                row["repeatedCommit"] = repeated.committedText
                row["selectionPassed"] = unexpected.isEmpty && selected.committedText == item.target &&
                    selected.input.isEmpty && selected.preedit.isEmpty && selected.candidates.isEmpty &&
                    repeated.committedText.isEmpty && repeated.input.isEmpty
            }
            timings += keyTimes; rows.append(row)
        }
        timings.sort()
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let percentile: (Double) -> Double = { timings.isEmpty ? 0 : timings[min(timings.count-1, Int(Double(timings.count)*$0))] }
        let result: [String: Any] = ["results": rows, "rankingLearnsAnswers": !commitID.isEmpty,
            "platform": "macOS native engine; peakRSS is not iOS extension footprint", "peakRSSBytes": usage.ru_maxrss,
            "startupMS": startupMS, "keyP50MS": percentile(0.5), "keyP95MS": percentile(0.95), "keyP99MS": percentile(0.99)]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[4]))
        print("\(rows.count) cases; P95 \(percentile(0.95)) ms; RSS \(usage.ru_maxrss)")
    }
}

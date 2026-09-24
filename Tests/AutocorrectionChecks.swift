import Foundation

struct CorrectionCase: Codable {
    let schema: String, kind: String, input: String, target: String, correct: String, split: String
}
@main struct AutocorrectionChecks {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count >= 5 else { fatalError("runner resources userdir cases.json output.json [baseline]") }
        let resource = URL(fileURLWithPath: CommandLine.arguments[1])
        let user = URL(fileURLWithPath: CommandLine.arguments[2])
        let cases = try JSONDecoder().decode([CorrectionCase].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
        let enabled = CommandLine.arguments.last != "baseline"
        let engine = try SKRimeEngine(schema: "shika_pinyin", resourceURL: resource, userURL: user, correctionEnabled: enabled)
        var rows: [[String: Any]] = [], schema = "", delays: [Double] = []
        for item in cases {
            if item.schema != schema { _ = try engine.selectSchema(item.schema); schema = item.schema }
            _ = engine.clear()
            var state = SKEngineState(), keystrokes: [Double] = []
            for ch in item.input.utf8 {
                let start = CFAbsoluteTimeGetCurrent()
                state = engine.process(key: Int32(ch))
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                keystrokes.append(ms); delays.append(ms)
            }
            let texts = state.candidates.map(\.text)
            let rank = texts.firstIndex(of: item.target).map { $0 + 1 } ?? 0
            // Select only in a separate replay run. Ranking measurements must not
            // train answers into later cases in the same evaluation.
            rows.append(["schema": item.schema, "kind": item.kind, "input": item.input, "target": item.target,
                         "correct": item.correct, "split": item.split, "rank": rank, "candidates": texts,
                         "indexes": state.candidates.map(\.index), "comments": state.candidates.map(\.comment),
                         "maxKeyMilliseconds": keystrokes.max() ?? 0])
        }
        delays.sort()
        let summary: [String: Any] = ["enabled": enabled, "cases": rows, "keyCount": delays.count,
                                     "p50Milliseconds": delays[delays.count / 2],
                                     "p95Milliseconds": delays[min(delays.count-1,Int(Double(delays.count)*0.95))],
                                     "maxMilliseconds": delays.last ?? 0]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[4]))
        for scheme in ["shika_pinyin", "shika_flypy"] {
            for kind in ["substitution", "omission", "insertion", "transposition", "clean", "boundary"] {
                let group = rows.filter { $0["schema"] as? String == scheme && $0["kind"] as? String == kind }
                let ranks = group.map { $0["rank"] as! Int }
                print("\(scheme) \(kind): n=\(group.count) top1=\(ranks.filter{$0==1}.count) top3=\(ranks.filter{(1...3).contains($0)}.count) visible=\(ranks.filter{$0>0}.count)")
            }
        }
        print("latency p50=\(summary["p50Milliseconds"]!) p95=\(summary["p95Milliseconds"]!) max=\(summary["maxMilliseconds"]!) ms")
    }
}

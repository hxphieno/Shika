// Independent frozen lexical quality evaluation: expected targets never enter Rime.
import Foundation
import Darwin

private struct Corpus: Decodable { let cases: [Item] }
private struct Item: Decodable {
    let id: String
    let kind: String
    let target: String
    let syllables: [String]
    let pinyin: String
    let shuangpin: String
}

@main
struct LexiconQualityChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 7 else { fatalError("Usage: runner resources user cases schema ranking|coverage output") }
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let schema = args[4]
        let coverage = args[5].hasPrefix("coverage")
        let caseID = args[5].split(separator: ":").dropFirst().first.map(String.init)
        #if SHIKA_HAS_CONVERSION_ENGINE
        let config = schema == "mixed" ? SKChineseJapaneseScheme.configuration(for: .mixed) : SKInputScheme(schemaID: schema)!.configuration
        #else
        let config = SKInputScheme(schemaID: schema)!.configuration
        #endif
        let start = DispatchTime.now().uptimeNanoseconds
        let engine: any SKInputEngine
        #if SHIKA_HAS_CONVERSION_ENGINE
        if schema == "mixed" {
            engine = try SKConversionEngine(configuration: config, resourceURL: URL(fileURLWithPath: args[1]), userURL: URL(fileURLWithPath: args[2]))
        } else {
            engine = try SKRimeEngine(configuration: config, resourceURL: URL(fileURLWithPath: args[1]), userURL: URL(fileURLWithPath: args[2]))
        }
        #else
        engine = try SKRimeEngine(configuration: config, resourceURL: URL(fileURLWithPath: args[1]), userURL: URL(fileURLWithPath: args[2]))
        #endif
        let startupMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        var results: [[String: Any]] = []
        for item in corpus.cases where caseID == nil || caseID == item.id {
            _ = engine.clear()
            let input = schema == "shika_flypy" ? item.shuangpin : item.pinyin
            var durations: [Double] = []
            var state = SKEngineState()
            var unexpected = ""
            for code in input.utf8 {
                let before = DispatchTime.now().uptimeNanoseconds
                state = engine.process(key: Int32(code))
                durations.append(Double(DispatchTime.now().uptimeNanoseconds - before) / 1e6)
                unexpected += state.committedText
            }
            let candidates = Array(state.candidates.prefix(10))
            var result: [String: Any] = ["id": item.id, "kind": item.kind, "schema": schema,
                "input": input, "target": item.target, "syllables": item.syllables,
                "preedit": state.preedit, "remainingInput": state.input,
                "candidates": candidates.map { ["text": $0.text, "comment": $0.comment, "index": $0.index] as [String: Any] },
                "rank": candidates.firstIndex(where: { $0.text == item.target }).map { $0 + 1 } ?? 0,
                "unexpectedCommit": unexpected, "keyDurationsMS": durations]
            // Coverage is a separate process/userdir; its selections cannot contaminate ranking.
            if coverage, let first = candidates.first {
                let selected = engine.selectCandidate(at: first.index)
                result["topChoiceConsumesAllInput"] = selected.input.isEmpty
                result["topChoiceOutput"] = selected.committedText
                result["remainingAfterTopChoice"] = selected.input
                result["topChoiceExactOutput"] = selected.input.isEmpty && selected.committedText == item.target
            }
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            result["processPeakRSSBytes"] = usage.ru_maxrss
            results.append(result)
        }
        let report: [String: Any] = ["schema": schema, "mode": args[5], "correctionEnabled": true,
            "platform": "macOS native librime (not iOS extension memory/latency)", "startupMS": startupMS,
            "caseCount": results.count, "rankingTraining": false, "results": results]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[6]))
        print("\(schema) \(args[5]): \(results.count) cases -> \(args[6])")
    }
}

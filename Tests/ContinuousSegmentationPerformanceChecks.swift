import Foundation

/// Measures path generation with a deterministic query spy. It does not measure
/// Rime latency or claim that synthetic candidate text is a useful phrase.
@main struct ContinuousSegmentationPerformanceChecks {
    static func main() throws {
        let args = CommandLine.arguments
        let resources = URL(fileURLWithPath: args[1])
        let inputs = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let config = SKInputConfiguration(schemaID: "shika_pinyin", inputPolicy: .chineseRomanization, spelling: .fullPinyin)
        var times: [String: [Double]] = [:], signatures: [String] = []
        var queryCount = 0
        for iteration in 0..<3 {
            for word in inputs {
                let presenter = SKPinyinSegmentationCandidates(resources: resources, configuration: config)!
                let prefixes = (1...max(1, word.count)).map { String(word.prefix($0)) }
                let phases: [(String, [String])] = [("cold", prefixes), ("delete", Array(prefixes.dropLast().reversed())), ("retype", prefixes)]
                for (phase, values) in phases {
                    for input in values {
                        let state = SKEngineState(input: input, preedit: input)
                        let start = DispatchTime.now().uptimeNanoseconds
                        let output = presenter.present(state) { path in
                            queryCount += 1
                            return SKEngineState(input: path, candidates: [SKCandidate(index: 0, text: phase + path, comment: path)])
                        }
                        times[phase, default: []].append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                        if iteration == 0 {
                            signatures.append(phase + ":" + input + ":" + output.candidates.map {
                                "\($0.index)|\($0.text)|\($0.comment)|\(presenter.selection(at: $0.index)?.code ?? "")"
                            }.joined(separator: ";"))
                        }
                    }
                }
            }
        }
        let timing = times.mapValues { values -> [String: Double] in
            let sorted = values.sorted()
            return ["count": Double(values.count), "totalMS": values.reduce(0, +), "p50MS": sorted[sorted.count / 2],
                    "p95MS": sorted[Int(Double(sorted.count) * 0.95)], "p99MS": sorted[Int(Double(sorted.count) * 0.99)]]
        }
        let result: [String: Any] = ["scope": "macOS segmentation presenter, deterministic query spy", "timings": timing,
                                   "queryCount": queryCount, "signatures": signatures]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: args[3]))
        print(timing)
    }
}

import Foundation

// Standalone lexicon measurement with the shipped dictionary. No learned rank
// or UI work is included; signatures contain the complete ordered conversion.
@main struct ContinuousJapanesePerformanceChecks {
    struct Corpus: Decodable { let cases: [Item] }
    struct Item: Decodable { let id: String; let romaji: String }
    static func main() throws {
        let args = CommandLine.arguments
        let resources = URL(fileURLWithPath: args[1])
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        var times: [String: [Double]] = [:], signatures: [String] = []
        for iteration in 0..<2 {
            for item in corpus.cases {
                let lexicon = try SKJapaneseLexicon(resources: resources)
                var seen = Set<String>()
                let readings = (1...item.romaji.count).compactMap { length -> String? in
                    let value = lexicon.reading(String(item.romaji.prefix(length)))
                    return value.pending.isEmpty && !value.kana.isEmpty && seen.insert(value.kana).inserted ? value.kana : nil
                }
                for (phase, inputs) in [("cold", readings), ("delete", Array(readings.dropLast().reversed())), ("retype", readings)] {
                    for input in inputs {
                        let start = DispatchTime.now().uptimeNanoseconds
                        let candidates = lexicon.convert(input)
                        times[phase, default: []].append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                        if iteration == 0 {
                            signatures.append(item.id + ":" + phase + ":" + input + ":" + candidates.joined(separator: "|"))
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
        let result: [String: Any] = ["scope": "macOS immutable Japanese conversion only", "timings": timing, "signatures": signatures]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: args[3]))
        print(timing)
    }
}

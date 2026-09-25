import Foundation

// Measures immutable spelling lookup only; separate from Rime and UI latency.
@main struct SpellingSearchPerformanceChecks {
    struct Case: Decodable { let schema: String; let input: String }
    static func main() throws {
        let args = CommandLine.arguments
        let resources = URL(fileURLWithPath: args[1])
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        var timings: [String: [Double]] = [:], signatures: [String] = []
        for iteration in 0..<3 {
            for item in cases {
                let config = SKInputConfiguration(schemaID: item.schema, inputPolicy: .chineseRomanization,
                    spelling: item.schema == "shika_flypy" ? .doublePinyin : .fullPinyin)
                guard let corrector = SKSpellingCorrector(resources: resources, configuration: config) else { fatalError("index unavailable") }
                let inputs = (1...max(1, item.input.count)).map { String(item.input.prefix($0)) }
                for pass in ["cold", "retype"] {
                    for input in inputs {
                        let start = DispatchTime.now().uptimeNanoseconds
                        let values = corrector.suggestions(for: input)
                        timings[item.schema + "." + pass, default: []].append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                        if iteration == 0 {
                            signatures.append(item.schema + ":" + pass + ":" + input + ":" + values.map { "\($0.code)|\($0.text)|\($0.cost)|\($0.frequency)" }.joined(separator: ";"))
                        }
                    }
                }
            }
        }
        let measurements = timings.mapValues { values -> [String: Double] in
            let sorted = values.sorted()
            return ["count": Double(sorted.count), "totalMS": values.reduce(0,+), "p50MS": sorted[sorted.count/2],
                "p95MS": sorted[Int(Double(sorted.count)*0.95)], "p99MS": sorted[Int(Double(sorted.count)*0.99)]]
        }
        let result: [String: Any] = ["platform": "macOS spelling lookup only", "timings": measurements, "signatures": signatures]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[3]))
        print(measurements)
    }
}

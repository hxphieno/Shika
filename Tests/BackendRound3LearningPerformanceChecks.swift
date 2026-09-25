import Foundation
import Darwin

// Isolates the bounded learned-code search; it does not measure Rime or typing.
@main struct BackendRound3LearningPerformanceChecks {
    struct Fixture: Decodable {
        let entries: [SKLearnedSpellingIndex.Entry]
        let inputs: [String]
    }
    static func main() throws {
        let args = CommandLine.arguments
        let fixtures = try JSONDecoder().decode([String: Fixture].self,
            from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let user = URL(fileURLWithPath: args[2])
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        var timings: [String: [Double]] = [:], signatures: [String] = []
        for schema in fixtures.keys.sorted() {
            let fixture = fixtures[schema]!
            let profile: SKSpellingProfile = schema == "shika_flypy" ? .doublePinyin : .fullPinyin
            let filename = profile == .doublePinyin ? "double-pinyin-spelling.json" : "full-pinyin-spelling.json"
            for capacity in [0, 64, 512] {
                try JSONEncoder().encode(Array(fixture.entries.prefix(capacity)))
                    .write(to: user.appendingPathComponent(filename))
                let index = SKLearnedSpellingIndex(userDirectory: user, profile: profile)
                let key = "\(schema).\(capacity)"
                for iteration in 0..<5 {
                    for input in fixture.inputs {
                        let start = DispatchTime.now().uptimeNanoseconds
                        let found = index.suggestions(for: input)
                        timings[key, default: []].append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                        if iteration == 0 {
                            signatures.append(key + ":" + input + ":" + found.map { $0.code + "|" + $0.text }.joined(separator: ";"))
                        }
                    }
                }
            }
        }
        let measurements = timings.mapValues { values -> [String: Double] in
            let sorted = values.sorted()
            return ["count": Double(values.count), "totalMS": values.reduce(0, +),
                "p50MS": sorted[sorted.count / 2], "p95MS": sorted[Int(Double(sorted.count) * 0.95)],
                "p99MS": sorted[Int(Double(sorted.count) * 0.99)]]
        }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let report: [String: Any] = ["platform": "macOS learned spelling lookup only",
            "timings": measurements, "signatures": signatures, "peakRSSBytes": usage.ru_maxrss]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: args[3]))
        print(measurements)
    }
}

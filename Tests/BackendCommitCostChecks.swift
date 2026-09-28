import Foundation
import Darwin

/// Measures real selection/learning cost; does not measure touch or extension memory.
@main struct BackendCommitCostChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let resources = URL(fileURLWithPath: args[1]), user = URL(fileURLWithPath: args[2])
        let engine = try SKRimeEngine(configuration: SKInputScheme.shuangpin.configuration, resourceURL: resources, userURL: user)
        let words = [("你好", "nihao", "nihk"), ("中国", "zhongguo", "vsgo"),
                     ("世界", "shijie", "uijx"), ("今天", "jintian", "jbtm"),
                     ("明天", "mingtian", "mktm"), ("天气", "tianqi", "tmqi")]
        var reports: [[String: Any]] = [], failures: [String] = []
        for schema in ["shika_flypy", "shika_pinyin"] {
            _ = try engine.selectConfiguration(SKInputScheme(schemaID: schema)!.configuration)
            var keys: [Double] = [], commits: [Double] = []
            for _ in 0..<20 {
                for (target, full, double) in words {
                    _ = engine.clear()
                    let code = schema == "shika_flypy" ? double : full
                    var state = SKEngineState()
                    for key in code.utf8 {
                        let start = DispatchTime.now().uptimeNanoseconds
                        state = engine.process(key: Int32(key))
                        keys.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                        if !state.committedText.isEmpty { failures.append("unexpected typing commit: \(code)") }
                    }
                    guard let choice = state.candidates.first(where: { $0.text == target }) else {
                        failures.append("missing \(code) → \(target)"); continue
                    }
                    let start = DispatchTime.now().uptimeNanoseconds
                    let committed = engine.selectCandidate(at: choice.index)
                    commits.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                    if committed.committedText != target || !committed.input.isEmpty || !committed.preedit.isEmpty || !committed.candidates.isEmpty {
                        failures.append("incomplete selection: \(code)")
                    }
                    if !engine.commit().committedText.isEmpty { failures.append("repeated commit: \(code)") }
                }
            }
            func stats(_ values: [Double]) -> [String: Any] {
                let sorted = values.sorted()
                return ["count": sorted.count, "p50MS": sorted[sorted.count / 2],
                        "p95MS": sorted[sorted.count * 95 / 100], "p99MS": sorted[sorted.count * 99 / 100],
                        "maxMS": sorted.last ?? 0]
            }
            reports.append(["schema": schema, "keys": stats(keys), "commits": stats(commits)])
        }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let result: [String: Any] = ["platform": "macOS native engine, optimized build, fresh user directory",
            "note": "Repeated fixed words measure selection/learning overhead, not ranking accuracy or natural usage.",
            "peakRSSBytes": usage.ru_maxrss, "profiles": reports, "failures": failures]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: args[3]))
        print("\(failures.isEmpty ? "PASS" : "FAIL") 240 selections: \(failures)")
        if !failures.isEmpty { exit(1) }
    }
}

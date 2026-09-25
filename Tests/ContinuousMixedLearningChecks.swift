// Independent guard transition checks: no history -> first actual selection -> reload.
import Foundation

@main struct ContinuousMixedLearningChecks {
    @MainActor static func main() throws {
        let a = CommandLine.arguments
        let resources = URL(fileURLWithPath: a[1]), user = URL(fileURLWithPath: a[2])
        let engine = try SKMixedEngine(resources: resources, userDirectory: user)
        let file = user.appendingPathComponent("mixed-learning.json")
        let raw = "jintianyearigatou", target = "今天也有難う"
        var checks: [[String: Any]] = []
        func check(_ name: String, _ ok: Bool) { checks.append(["name": name, "passed": ok]) }
        func type() -> SKEngineState {
            _ = engine.clear(); var state = SKEngineState()
            for byte in raw.utf8 { state = engine.process(key: Int32(byte)) }
            return state
        }
        func candidates() -> [SKCandidate] { engine.candidatePage(startingAt: 0, limit: 64).candidates }
        func records() -> [String: Int] {
            Mirror(reflecting: engine).children.first { $0.label == "learned" }?.value as? [String: Int] ?? [:]
        }
        var beforeRank = -1, afterRank = -1
        if a.count > 4 && a[4] == "reload" {
            let saved = try Data(contentsOf: file)
            check("new process loads first selection history", !records().isEmpty && records().values.allSatisfy { $0 == 1 })
            _ = type(); let first = candidates()
            let old = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[5]))) as! [String: Any]
            check("new process preserves exact post-first-selection order", first.map(\.text) == old["afterTexts"] as? [String])
            _ = engine.process(key: 0xff0d)
            _ = type(); _ = engine.clear()
            check("Return and cancellation do not alter persisted history", try Data(contentsOf: file) == saved)
        } else {
            check("fresh engine starts without learned records", records().isEmpty && !FileManager.default.fileExists(atPath: file.path))
            _ = type(); let untouched = candidates()
            beforeRank = untouched.firstIndex { $0.text == target } ?? -1
            check("independent target present below initial first", beforeRank > 0)
            check("typing and browsing do not enable history", records().isEmpty && !FileManager.default.fileExists(atPath: file.path))
            let returned = engine.process(key: 0xff0d)
            check("Return keeps original spelling and clears", returned.committedText == raw && returned.input.isEmpty)
            check("Return leaves learning empty", records().isEmpty && !FileManager.default.fileExists(atPath: file.path))
            _ = type(); _ = engine.clear()
            check("cancel leaves learning empty", records().isEmpty && !FileManager.default.fileExists(atPath: file.path))
            _ = type()
            guard let choice = candidates().first(where: { $0.text == target }) else { fatalError("Fixed target missing") }
            let result = engine.selectCandidate(at: choice.index)
            check("first explicit selection commits exactly", result.committedText == target && result.input.isEmpty)
            check("first selection immediately disables empty-history fast path", !records().isEmpty)
            check("first selection records one use without hidden training", records().values.allSatisfy { $0 == 1 })
            check("first selection includes word and transition learning", records().keys.contains { $0.hasPrefix("w:") } && records().keys.contains { $0.hasPrefix("p:") })
            let saved = try Data(contentsOf: file)
            _ = type(); let after = candidates()
            afterRank = after.firstIndex { $0.text == target } ?? -1
            check("first selection already improves live candidate rank", afterRank >= 0 && afterRank < beforeRank)
            let repeated = candidates()
            check("browsing remains deterministic with enabled learning", repeated == after)
            _ = engine.clear()
            check("clear keeps enabled learned state", !records().isEmpty && (try? Data(contentsOf: file)) == saved)
        }
        _ = type(); let final = candidates()
        let failed = checks.filter { $0["passed"] as? Bool != true }
        try JSONSerialization.data(withJSONObject: ["checks": checks, "passed": checks.count - failed.count, "failed": failed.count, "beforeRankZeroBased": beforeRank, "afterRankZeroBased": afterRank, "afterTexts": final.map(\.text), "scope": "Real mixed decoder empty-history fast-path transition; no mocks"], options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: a[3]))
        print("\(checks.count-failed.count)/\(checks.count) passed; rank \(beforeRank)->\(afterRank)")
        if !failed.isEmpty { exit(1) }
    }
}

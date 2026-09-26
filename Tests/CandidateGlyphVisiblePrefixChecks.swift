// Focused real-Rime regression: an automatic flush may not implicitly select an
// unchecked tail after choosing the sole visible prefix. Visibility is injected
// to isolate this route; this does not claim 调拨 is actually missing a glyph.
import Foundation

@main struct CandidateGlyphVisiblePrefixChecks {
    @MainActor static func main() async throws {
        let a = CommandLine.arguments
        let engine = try SKRimeEngine(configuration: SKShuangpinScheme.configuration,
            resourceURL: URL(fileURLWithPath: a[1]), userURL: URL(fileURLWithPath: a[2]))
        var output = ""
        let session = SKInputSession(engine: engine, configuration: SKShuangpinScheme.configuration,
            candidateIsDisplayable: { $0 == "颠簸" }, insertText: { output += $0 }, deleteText: {})
        for c in "dmbodnbo" { session.type(String(c)) }
        for _ in 0..<1000 where !session.state.isLastPage { await Task.yield() }
        let before = session.state.candidates
        session.type("，")
        let passed = before.first?.text == "颠簸" && output == "颠簸dnbo，" && session.state.input.isEmpty
        let report: [String: Any] = ["passed": passed, "expected": "颠簸dnbo，", "actual": output,
            "visibleBeforeFlush": before.map { ["index": $0.index, "text": $0.text, "comment": $0.comment] as [String: Any] },
            "remaining": session.state.input, "scope": "Real Rime; only visibility policy injected to reproduce partial-flush route"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: a[3]))
        print("visible-prefix automatic flush: \(passed), output=\(output)")
        if !passed { exit(1) }
    }
}

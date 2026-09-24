// Independent heldout evaluation. Ranking and commit runs use separate processes
// and fresh user directories so candidate selection cannot train ranking cases.
import Foundation

private struct Case: Decodable {
    let schema: String
    let kind: String
    let input: String
    let target: String
    let correct: String
    let split: String
}

@main
struct AutocorrectionIndependentChecks {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 7 else {
            fatalError("Usage: independent-checks resources user cases.json enabled|disabled ranking|commit output.json")
        }
        let args = CommandLine.arguments
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let enabled = args[4] == "enabled"
        let testCommit = args[5] == "commit"
        let engine = try SKRimeEngine(schema: cases[0].schema,
            resourceURL: URL(fileURLWithPath: args[1]), userURL: URL(fileURLWithPath: args[2]), correctionEnabled: enabled)
        var schema = cases[0].schema
        var output = ""
        let session = SKInputSession(engine: engine, insertText: { output += $0 }, deleteText: { if !output.isEmpty { output.removeLast() } })
        var results: [[String: Any]] = []
        for item in cases {
            session.cancel()
            if schema != item.schema { try session.switchSchema(to: item.schema); schema = item.schema }
            output = ""
            var durations: [Double] = []
            for character in item.input {
                let start = Date()
                session.type(String(character))
                durations.append(Date().timeIntervalSince(start) * 1000)
            }
            let state = session.state
            let candidates = state.candidates
            var row: [String: Any] = [
                "schema": item.schema, "kind": item.kind, "input": item.input,
                "target": item.target, "correct": item.correct,
                "candidates": candidates.map { ["text": $0.text, "comment": $0.comment, "index": $0.index] as [String: Any] },
                "targetRank": candidates.firstIndex(where: { $0.text == item.target }).map { $0 + 1 } ?? 0,
                "inputRemaining": state.input, "preedit": state.preedit,
                "unexpectedOutputBeforeSelection": output,
                "keyDurationsMS": durations
            ]
            if testCommit {
                if let candidate = candidates.first(where: { $0.text == item.target }) {
                    session.select(candidate)
                    row["selectedOutput"] = output
                    row["selectionCleared"] = session.state.input.isEmpty && session.state.candidates.isEmpty
                    row["selectedExactlyOnce"] = output == item.target
                    row["remainingAfterSelection"] = session.state.input
                } else {
                    row["selectionUnavailable"] = true
                }
                // Space must commit the displayed top choice in its own composition.
                session.cancel(); output = ""
                for character in item.input { session.type(String(character)) }
                let displayedTop = session.state.candidates.first?.text ?? ""
                session.type(" ")
                row["spaceDisplayedTop"] = displayedTop
                row["spaceOutput"] = output
                let partialSelection = output.isEmpty && !session.state.input.isEmpty && session.state.preedit.hasPrefix(displayedTop)
                row["spaceMatchesDisplayedTop"] = displayedTop.isEmpty || output == displayedTop || partialSelection
                row["spacePartialSelection"] = partialSelection
                row["spacePreeditAfterSelection"] = session.state.preedit
                row["spaceRemaining"] = session.state.input
            }
            results.append(row)
        }
        let report: [String: Any] = ["correctionEnabled": enabled, "mode": args[5], "caseCount": results.count, "results": results]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: args[6]))
        print("Independent \(args[4]) \(args[5]): \(results.count) cases -> \(args[6])")
    }
}
